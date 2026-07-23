import {Camera} from 'lucide-react';
import {useRef} from 'react';
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

export function CameraScreen({
  locale,
  text,
  onLocaleChange,
  onCapture,
  onError,
}: CameraScreenProps) {
  const webcamRef = useRef<Webcam>(null);

  const handleCapture = () => {
    const image = webcamRef.current?.getScreenshot();
    if (!image) {
      onError('CAPTURE_FAILED');
      return;
    }

    onCapture(image);
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
          onUserMedia={() => undefined}
          onUserMediaError={() => onError('CAMERA_DENIED')}
          className="camera-video"
        />
        <div className="camera-frame" aria-hidden="true">
          <span />
          <span />
          <span />
          <span />
        </div>
      </div>

      <section className="camera-controls" aria-label={text.cameraReady}>
        <div className="camera-guidance">
          <span className="ready-indicator" aria-hidden="true" />
          <div>
            <strong>{text.cameraReady}</strong>
            <p>{text.cameraHint}</p>
          </div>
        </div>
        <button
          className="shutter-button"
          type="button"
          aria-label={text.capture}
          onClick={handleCapture}
        >
          <Camera aria-hidden="true" size={28} />
        </button>
      </section>
    </main>
  );
}
