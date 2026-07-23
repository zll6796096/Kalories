import {useEffect, useReducer, useRef} from 'react';

import {AnalysisApiError, analyzeImage} from './api';
import {messages, persistLocale, resolveLocale, type Messages} from './i18n';
import {
  ImagePreparationError,
  prepareImageForAnalysis,
} from './image';
import {AnalyzingScreen} from './screens/AnalyzingScreen';
import {CameraScreen} from './screens/CameraScreen';
import {IntroScreen} from './screens/IntroScreen';
import {ResultScreen} from './screens/ResultScreen';
import type {
  AnalysisResult,
  AppErrorCode,
  AppState,
  Locale,
} from './types';

export interface AppModel {
  appState: AppState;
  locale: Locale;
  analysisResult: AnalysisResult | null;
  error: AppErrorCode | null;
  saveError: boolean;
  capturedImage: string | null;
  latestRequestId: number;
}

export type AppModelAction =
  | {type: 'locale-changed'; locale: Locale}
  | {type: 'retake'; nextRequestId: number}
  | {type: 'analysis-started'; requestId: number; image: string}
  | {
      type: 'analysis-succeeded';
      requestId: number;
      result: AnalysisResult;
    }
  | {
      type: 'analysis-failed';
      requestId: number;
      code: AppErrorCode;
    }
  | {type: 'camera-error'; code: AppErrorCode}
  | {type: 'save-started' | 'save-succeeded' | 'save-failed'};

const errorMessageKeys = {
  CAMERA_DENIED: 'errorCameraDenied',
  CAPTURE_FAILED: 'errorCaptureFailed',
  INVALID_IMAGE: 'errorInvalidImage',
  UNSUPPORTED_IMAGE: 'errorUnsupportedImage',
  IMAGE_TOO_LARGE: 'errorImageTooLarge',
  NO_FOOD: 'errorNoFood',
  SERVICE_NOT_CONFIGURED: 'errorServiceNotConfigured',
  ANALYSIS_FAILED: 'errorAnalysisFailed',
  NETWORK_ERROR: 'errorNetwork',
  SAVE_FAILED: 'errorSaveFailed',
} as const satisfies Record<AppErrorCode, keyof Messages>;

const retryableCameraErrors = new Set<AppErrorCode>([
  'INVALID_IMAGE',
  'UNSUPPORTED_IMAGE',
  'IMAGE_TOO_LARGE',
  'SERVICE_NOT_CONFIGURED',
  'ANALYSIS_FAILED',
  'NETWORK_ERROR',
]);

export function errorMessageKey(code: AppErrorCode): keyof Messages {
  return errorMessageKeys[code];
}

export function createInitialAppModel(
  locale: Locale,
  latestRequestId = 0,
  appState: AppState = 'intro',
): AppModel {
  return {
    appState,
    locale,
    analysisResult: null,
    error: null,
    saveError: false,
    capturedImage: null,
    latestRequestId,
  };
}

export function imageForRetry(model: AppModel): string | null {
  return model.capturedImage;
}

export function appModelReducer(
  model: AppModel,
  action: AppModelAction,
): AppModel {
  switch (action.type) {
    case 'locale-changed':
      return {...model, locale: action.locale};
    case 'retake':
      return createInitialAppModel(
        model.locale,
        action.nextRequestId,
        'camera',
      );
    case 'analysis-started':
      return {
        ...model,
        appState: 'analyzing',
        analysisResult: null,
        error: null,
        saveError: false,
        capturedImage: action.image,
        latestRequestId: action.requestId,
      };
    case 'analysis-succeeded':
      if (action.requestId !== model.latestRequestId) {
        return model;
      }
      return {
        ...model,
        appState: 'result',
        analysisResult: action.result,
        error: action.result.food_detected ? null : 'NO_FOOD',
        saveError: false,
      };
    case 'analysis-failed':
      if (action.requestId !== model.latestRequestId) {
        return model;
      }
      return {
        ...model,
        appState: 'camera',
        analysisResult: null,
        error: action.code,
        saveError: false,
      };
    case 'camera-error':
      return {
        ...model,
        appState: 'camera',
        analysisResult: null,
        error: action.code,
        saveError: false,
      };
    case 'save-started':
    case 'save-succeeded':
      return {...model, saveError: false};
    case 'save-failed':
      return {...model, saveError: true};
  }
}

export function abortActiveRequest(
  controller: AbortController | null,
): void {
  controller?.abort();
}

export function replaceActiveRequest(
  controller: AbortController | null,
): AbortController {
  abortActiveRequest(controller);
  return new AbortController();
}

function analysisErrorCode(error: unknown): AppErrorCode {
  if (
    error instanceof AnalysisApiError ||
    error instanceof ImagePreparationError
  ) {
    return error.code;
  }
  return 'ANALYSIS_FAILED';
}

export default function App() {
  const [model, dispatch] = useReducer(
    appModelReducer,
    createInitialAppModel(resolveLocale()),
  );
  const requestSequence = useRef(0);
  const activeRequest = useRef<AbortController | null>(null);
  const text = messages[model.locale];

  useEffect(
    () => () => {
      requestSequence.current += 1;
      abortActiveRequest(activeRequest.current);
      activeRequest.current = null;
    },
    [],
  );

  const handleLocaleChange = (locale: Locale) => {
    dispatch({type: 'locale-changed', locale});
    persistLocale(locale);
  };

  const handleRetake = () => {
    const nextRequestId = ++requestSequence.current;
    abortActiveRequest(activeRequest.current);
    activeRequest.current = null;
    dispatch({type: 'retake', nextRequestId});
  };

  const runAnalysis = async (image: string) => {
    if (!image) {
      dispatch({type: 'camera-error', code: 'CAPTURE_FAILED'});
      return;
    }

    const controller = replaceActiveRequest(activeRequest.current);
    activeRequest.current = controller;
    const requestId = ++requestSequence.current;
    dispatch({type: 'analysis-started', requestId, image});

    try {
      const preparedImage = await prepareImageForAnalysis(image);
      if (
        controller.signal.aborted ||
        requestId !== requestSequence.current
      ) {
        return;
      }

      const result = await analyzeImage(preparedImage, {
        signal: controller.signal,
      });
      dispatch({type: 'analysis-succeeded', requestId, result});
    } catch (error) {
      if (requestId !== requestSequence.current) {
        return;
      }
      dispatch({
        type: 'analysis-failed',
        requestId,
        code: analysisErrorCode(error),
      });
    } finally {
      if (activeRequest.current === controller) {
        activeRequest.current = null;
      }
    }
  };

  const handleRetry = () => {
    const image = imageForRetry(model);
    if (!image) {
      dispatch({type: 'camera-error', code: 'CAPTURE_FAILED'});
      return;
    }
    void runAnalysis(image);
  };

  const primaryErrorText = model.error
    ? text[errorMessageKey(model.error)]
    : null;
  const saveErrorText = model.saveError ? text.errorSaveFailed : null;
  const showCameraRetry =
    model.appState === 'camera' &&
    model.capturedImage !== null &&
    model.error !== null &&
    retryableCameraErrors.has(model.error);

  return (
    <div className="app-shell">
      {(primaryErrorText || saveErrorText) && (
        <aside
          className={`app-error-panel app-error-${model.appState}`}
          role="alert"
        >
          {primaryErrorText && <p>{primaryErrorText}</p>}
          {saveErrorText && <p>{saveErrorText}</p>}
          {showCameraRetry && (
            <button className="text-button" type="button" onClick={handleRetry}>
              {text.retry}
            </button>
          )}
        </aside>
      )}

      {model.appState === 'intro' && (
        <IntroScreen
          locale={model.locale}
          text={text}
          onLocaleChange={handleLocaleChange}
          onStart={handleRetake}
        />
      )}

      {model.appState === 'camera' && (
        <CameraScreen
          locale={model.locale}
          text={text}
          onLocaleChange={handleLocaleChange}
          onCapture={(image) => void runAnalysis(image)}
          onError={(code) => dispatch({type: 'camera-error', code})}
        />
      )}

      {model.appState === 'analyzing' && (
        <AnalyzingScreen
          locale={model.locale}
          text={text}
          capturedImage={model.capturedImage}
          onLocaleChange={handleLocaleChange}
        />
      )}

      {model.appState === 'result' && model.analysisResult && (
        <ResultScreen
          locale={model.locale}
          text={text}
          data={model.analysisResult}
          capturedImage={model.capturedImage}
          onLocaleChange={handleLocaleChange}
          onRetry={handleRetry}
          onRetake={handleRetake}
          onSaveStart={() => dispatch({type: 'save-started'})}
          onSaveSuccess={() => dispatch({type: 'save-succeeded'})}
          onSaveError={() => dispatch({type: 'save-failed'})}
        />
      )}
    </div>
  );
}
