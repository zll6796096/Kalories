import {renderToStaticMarkup} from 'react-dom/server';
import {describe, expect, it} from 'vitest';

import {messages} from '../i18n';
import {
  CameraScreen,
  cameraReadinessReducer,
} from './CameraScreen';

const renderCamera = () =>
  renderToStaticMarkup(
    <CameraScreen
      locale="en"
      text={messages.en}
      onLocaleChange={() => undefined}
      onCapture={() => undefined}
      onError={() => undefined}
    />,
  );

describe('CameraScreen readiness', () => {
  it('starts with the shutter disabled and no green ready state', () => {
    const html = renderCamera();

    expect(html).toContain('aria-disabled="true"');
    expect(html).toContain('disabled=""');
    expect(html).not.toContain('ready-indicator is-ready');
  });

  it('becomes ready only when video frame dimensions are usable', () => {
    expect(
      cameraReadinessReducer(false, {
        type: 'video-data',
        width: 1280,
        height: 720,
      }),
    ).toBe(true);
    expect(
      cameraReadinessReducer(false, {
        type: 'video-data',
        width: 1280,
        height: 0,
      }),
    ).toBe(false);
  });

  it('clears readiness after a media error', () => {
    expect(cameraReadinessReducer(true, {type: 'media-error'})).toBe(false);
  });
});
