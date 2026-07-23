import {Camera} from 'lucide-react';
import {useReducer, useRef, type SyntheticEvent} from 'react';
import Webcam from 'react-webcam';

import {LanguageSwitcher} from '../components/LanguageSwitcher';
import type {Messages} from '../i18n';
import type {AppErrorCode, Locale} from '../types';

interface CameraScreenProps {
  locale: Locale;
  text: Messages;
  onLocaleChange: (locale: Locale) => void;
  onCapture: (image: string) => void;
  onError: (code: AppErrorCode) => void;
}

const videoConstraints: MediaTrackConstraints = {
  facingMode: {ideal: 'environment'},
  width: {ideal: 1280},
  height: {ideal: 1280},
};

export type CameraReadinessAction =
  | {type: 'video-data'; width: number; height: number}
  | {type: 'media-error'};

export function cameraReadinessReducer(
  _isReady: boolean,
  action: CameraReadinessAction,
): boolean {
  if (action.type === 'media-error') {
    return false;
  }

  return action.width > 0 && action.height > 0;
}

export function CameraScreen({
  locale,
  text,
  onLocaleChange,
  onCapture,
  onError,
}: CameraScreenProps) {
  const webcamRef = useRef<Webcam>(null);
  const [isCameraReady, dispatchReadiness] = useReducer(
    cameraReadinessReducer,
    false,
  );

  const updateReadiness = (video: HTMLVideoElement | null | undefined) => {
    dispatchReadiness({
      type: 'video-data',
      width: video?.videoWidth ?? 0,
      height: video?.videoHeight ?? 0,
    });
  };

  const handleCapture = () => {
    const video = webcamRef.current?.video;
    if (
      !isCameraReady ||
      !video ||
      video.videoWidth <= 0 ||
      video.videoHeight <= 0
    ) {
      updateReadiness(video);
      return;
    }

    const image = webcamRef.current?.getScreenshot();
    if (!image) {
      onError('CAPTURE_FAILED');
      return;
    }

    onCapture(image);
  };

  const handleVideoData = (event: SyntheticEvent<HTMLVideoElement>) => {
    updateReadiness(event.currentTarget);
  };

  const handleMediaError = () => {
    dispatchReadiness({type: 'media-error'});
    onError('CAMERA_DENIED');
  };

  return (
    <main className="app-screen camera-screen">
      <header className="camera-toolbar">
        <div>
          <span className="wordmark wordmark-light">{text.appName}</span>
          <h1>{text.cameraTitle}</h1>
        </div>
        <LanguageSwitcher locale={locale} onChange={onLocaleChange} />
      </header>

      <div className="camera-viewport">
        <Webcam
          ref={webcamRef}
          audio={false}
          muted
          playsInline
          screenshotFormat="image/jpeg"
          screenshotQuality={0.82}
          forceScreenshotSourceSize={false}
          disablePictureInPicture={false}
          imageSmoothing
          mirrored={false}
          videoConstraints={videoConstraints}
          onLoadedData={handleVideoData}
          onCanPlay={handleVideoData}
          onUserMedia={() => updateReadiness(webcamRef.current?.video)}
          onUserMediaError={handleMediaError}
          className="camera-video"
        />
        <div className="camera-frame" aria-hidden="true">
          <span />
          <span />
          <span />
          <span />
        </div>
      </div>

      <section
        className="camera-controls"
        aria-label={isCameraReady ? text.cameraReady : text.cameraHint}
      >
        <div className="camera-guidance">
          <span
            className={`ready-indicator${isCameraReady ? ' is-ready' : ''}`}
            aria-hidden="true"
          />
          <div>
            <strong>{isCameraReady ? text.cameraReady : text.cameraTitle}</strong>
            <p>{text.cameraHint}</p>
          </div>
        </div>
        <button
          className="shutter-button"
          type="button"
          aria-label={text.capture}
          aria-disabled={!isCameraReady}
          disabled={!isCameraReady}
          onClick={handleCapture}
        >
          <Camera aria-hidden="true" size={28} />
        </button>
      </section>
    </main>
  );
}
