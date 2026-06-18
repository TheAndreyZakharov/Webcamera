package com.theandreyzakharov.webcamera.camera;

import android.graphics.ImageFormat;
import android.graphics.SurfaceTexture;
import android.hardware.Camera;
import android.util.Log;

import com.theandreyzakharov.webcamera.encoder.VideoEncoder;

import java.io.IOException;
import java.util.List;

@SuppressWarnings("deprecation")
public final class CameraController
    implements Camera.PreviewCallback {

    private static final String TAG =
        "WebcameraCamera";

    private final Object lock = new Object();
    private final VideoEncoder encoder;

    private Camera camera;
    private SurfaceTexture previewTexture;
    private CameraConfiguration configuration;

    private boolean streaming;
    private boolean torchEnabled;

    public CameraController(
        VideoEncoder encoder
    ) {
        this.encoder = encoder;
        this.configuration =
            CameraConfiguration.defaults();
    }

    public void configure(
        CameraConfiguration newConfiguration
    ) {
        synchronized (lock) {
            if (streaming) {
                throw new IllegalStateException(
                    "Stop streaming before changing configuration."
                );
            }

            configuration = newConfiguration;
        }
    }

    public CameraConfiguration getConfiguration() {
        synchronized (lock) {
            return configuration;
        }
    }

    public boolean isStreaming() {
        synchronized (lock) {
            return streaming;
        }
    }

    public boolean isTorchEnabled() {
        synchronized (lock) {
            return torchEnabled;
        }
    }

    public void start() throws IOException {
        synchronized (lock) {
            if (streaming) {
                return;
            }

            Camera openedCamera = null;

            try {
                openedCamera =
                    Camera.open(
                        configuration.cameraId
                    );

                if (openedCamera == null) {
                    throw new IOException(
                        "Camera.open returned null."
                    );
                }

                Camera.Parameters parameters =
                    openedCamera.getParameters();

                Camera.Size size =
                    selectPreviewSize(
                        parameters,
                        configuration.width,
                        configuration.height
                    );

                parameters.setPreviewSize(
                    size.width,
                    size.height
                );

                parameters.setPreviewFormat(
                    ImageFormat.NV21
                );

                int[] fpsRange =
                    selectFpsRange(
                        parameters,
                        configuration.frameRate
                    );

                if (fpsRange != null) {
                    parameters.setPreviewFpsRange(
                        fpsRange[0],
                        fpsRange[1]
                    );
                }

                applyFocusMode(
                    parameters,
                    configuration.focusMode
                );

                applyZoom(
                    parameters,
                    configuration.zoom
                );

                applyFlashMode(
                    parameters,
                    configuration.flashMode
                );

                openedCamera.setParameters(parameters);

                Camera.Parameters appliedParameters =
                    openedCamera.getParameters();

                Camera.Size appliedSize =
                    appliedParameters.getPreviewSize();

                CameraConfiguration appliedConfiguration =
                    new CameraConfiguration(
                        configuration.cameraId,
                        appliedSize.width,
                        appliedSize.height,
                        configuration.frameRate,
                        configuration.videoBitRate,
                        configuration.audioEnabled,
                        configuration.audioBitRate,
                        appliedParameters.getFocusMode(),
                        appliedParameters.getFlashMode() != null
                            ? appliedParameters.getFlashMode()
                            : "off",
                        zoomRatio(appliedParameters)
                    );

                configuration =
                    appliedConfiguration;

                encoder.start(
                    appliedSize.width,
                    appliedSize.height,
                    configuration.frameRate,
                    configuration.videoBitRate,
                    configuration.audioEnabled,
                    configuration.audioBitRate
                );

                previewTexture =
                    new SurfaceTexture(10);

                openedCamera.setPreviewTexture(
                    previewTexture
                );

                int bitsPerPixel =
                    ImageFormat.getBitsPerPixel(
                        ImageFormat.NV21
                    );

                int bufferSize =
                    appliedSize.width
                        * appliedSize.height
                        * bitsPerPixel
                        / 8;

                for (int index = 0; index < 4; index++) {
                    openedCamera.addCallbackBuffer(
                        new byte[bufferSize]
                    );
                }

                openedCamera.setPreviewCallbackWithBuffer(
                    this
                );

                openedCamera.startPreview();

                camera = openedCamera;
                streaming = true;

                String flashMode =
                    appliedParameters.getFlashMode();

                torchEnabled =
                    Camera.Parameters.FLASH_MODE_TORCH
                        .equals(flashMode);

                Log.i(
                    TAG,
                    "Camera started: "
                        + appliedSize.width
                        + "x"
                        + appliedSize.height
                );
            } catch (Exception exception) {
                if (openedCamera != null) {
                    try {
                        openedCamera.setPreviewCallbackWithBuffer(
                            null
                        );
                    } catch (RuntimeException ignored) {
                    }

                    try {
                        openedCamera.stopPreview();
                    } catch (RuntimeException ignored) {
                    }

                    openedCamera.release();
                }

                encoder.stop();
                releasePreviewTexture();

                if (exception instanceof IOException) {
                    throw (IOException) exception;
                }

                throw new IOException(
                    "Unable to start camera: "
                        + exception.getMessage(),
                    exception
                );
            }
        }
    }

    public void stop() {
        synchronized (lock) {
            streaming = false;
            torchEnabled = false;

            Camera currentCamera = camera;
            camera = null;

            if (currentCamera != null) {
                try {
                    currentCamera.setPreviewCallbackWithBuffer(
                        null
                    );
                } catch (RuntimeException ignored) {
                }

                try {
                    Camera.Parameters parameters =
                        currentCamera.getParameters();

                    List<String> flashModes =
                        parameters.getSupportedFlashModes();

                    if (flashModes != null
                        && flashModes.contains(
                            Camera.Parameters
                                .FLASH_MODE_OFF
                        )) {
                        parameters.setFlashMode(
                            Camera.Parameters
                                .FLASH_MODE_OFF
                        );

                        currentCamera.setParameters(
                            parameters
                        );
                    }
                } catch (RuntimeException ignored) {
                }

                try {
                    currentCamera.stopPreview();
                } catch (RuntimeException ignored) {
                }

                try {
                    currentCamera.release();
                } catch (RuntimeException ignored) {
                }
            }

            releasePreviewTexture();
            encoder.stop();

            Log.i(TAG, "Camera stopped");
        }
    }

    public boolean setTorchEnabled(
        boolean enabled
    ) {
        synchronized (lock) {
            Camera currentCamera = camera;

            if (currentCamera == null) {
                torchEnabled = false;

                configuration =
                    configuration.withFlashMode(
                        enabled ? "torch" : "off"
                    );

                return false;
            }

            try {
                Camera.Parameters parameters =
                    currentCamera.getParameters();

                List<String> modes =
                    parameters.getSupportedFlashModes();

                String requestedMode =
                    enabled
                        ? Camera.Parameters.FLASH_MODE_TORCH
                        : Camera.Parameters.FLASH_MODE_OFF;

                if (modes == null
                    || !modes.contains(requestedMode)) {
                    return false;
                }

                parameters.setFlashMode(requestedMode);
                currentCamera.setParameters(parameters);

                torchEnabled = enabled;

                configuration =
                    configuration.withFlashMode(
                        enabled ? "torch" : "off"
                    );

                return true;
            } catch (RuntimeException exception) {
                Log.e(
                    TAG,
                    "Unable to change torch state",
                    exception
                );

                return false;
            }
        }
    }

    public boolean setZoom(
        double requestedZoom
    ) {
        synchronized (lock) {
            Camera currentCamera = camera;

            if (currentCamera == null) {
                return false;
            }

            try {
                Camera.Parameters parameters =
                    currentCamera.getParameters();

                if (!parameters.isZoomSupported()) {
                    return false;
                }

                List<Integer> ratios =
                    parameters.getZoomRatios();

                if (ratios == null || ratios.isEmpty()) {
                    return false;
                }

                int requestedRatio =
                    (int) Math.round(
                        requestedZoom * 100.0
                    );

                int bestIndex = 0;
                int bestDistance = Integer.MAX_VALUE;

                for (int index = 0;
                     index < ratios.size();
                     index++) {
                    int distance =
                        Math.abs(
                            ratios.get(index)
                                - requestedRatio
                        );

                    if (distance < bestDistance) {
                        bestDistance = distance;
                        bestIndex = index;
                    }
                }

                parameters.setZoom(bestIndex);
                currentCamera.setParameters(parameters);

                double appliedZoom =
                    ratios.get(bestIndex) / 100.0;

                configuration =
                    configuration.withZoom(
                        appliedZoom
                    );

                return true;
            } catch (RuntimeException exception) {
                Log.e(
                    TAG,
                    "Unable to change zoom",
                    exception
                );

                return false;
            }
        }
    }

    public void requestKeyFrame() {
        encoder.requestKeyFrame();
    }

    @Override
    public void onPreviewFrame(
        byte[] data,
        Camera sourceCamera
    ) {
        boolean shouldEncode;

        synchronized (lock) {
            shouldEncode =
                streaming
                    && sourceCamera == camera;
        }

        if (shouldEncode) {
            encoder.queueVideoFrame(
                data,
                System.nanoTime()
            );
        }

        if (sourceCamera != null && data != null) {
            try {
                sourceCamera.addCallbackBuffer(data);
            } catch (RuntimeException ignored) {
            }
        }
    }

    private static Camera.Size selectPreviewSize(
        Camera.Parameters parameters,
        int requestedWidth,
        int requestedHeight
    ) {
        List<Camera.Size> sizes =
            parameters.getSupportedPreviewSizes();

        Camera.Size best = null;
        long bestScore = Long.MAX_VALUE;

        if (sizes != null) {
            for (Camera.Size size : sizes) {
                long widthDifference =
                    Math.abs(
                        size.width - requestedWidth
                    );

                long heightDifference =
                    Math.abs(
                        size.height - requestedHeight
                    );

                long score =
                    widthDifference * 10_000L
                        + heightDifference;

                if (score < bestScore) {
                    bestScore = score;
                    best = size;
                }
            }
        }

        if (best != null) {
            return best;
        }

        return parameters.getPreviewSize();
    }

    private static int[] selectFpsRange(
        Camera.Parameters parameters,
        int requestedFps
    ) {
        List<int[]> ranges =
            parameters.getSupportedPreviewFpsRange();

        if (ranges == null || ranges.isEmpty()) {
            return null;
        }

        int requested = requestedFps * 1000;
        int[] best = null;
        long bestScore = Long.MAX_VALUE;

        for (int[] range : ranges) {
            if (range == null || range.length < 2) {
                continue;
            }

            long containmentPenalty =
                requested >= range[0]
                    && requested <= range[1]
                    ? 0
                    : 10_000_000L;

            long score =
                containmentPenalty
                    + Math.abs(
                        range[1] - requested
                    )
                    + Math.abs(
                        range[0] - requested
                    );

            if (score < bestScore) {
                bestScore = score;
                best = range;
            }
        }

        return best;
    }

    private static void applyFocusMode(
        Camera.Parameters parameters,
        String requestedMode
    ) {
        List<String> modes =
            parameters.getSupportedFocusModes();

        if (modes == null || modes.isEmpty()) {
            return;
        }

        if (requestedMode != null
            && modes.contains(requestedMode)) {
            parameters.setFocusMode(requestedMode);
            return;
        }

        if (modes.contains(
            Camera.Parameters
                .FOCUS_MODE_CONTINUOUS_VIDEO
        )) {
            parameters.setFocusMode(
                Camera.Parameters
                    .FOCUS_MODE_CONTINUOUS_VIDEO
            );

            return;
        }

        if (modes.contains(
            Camera.Parameters.FOCUS_MODE_AUTO
        )) {
            parameters.setFocusMode(
                Camera.Parameters.FOCUS_MODE_AUTO
            );
        }
    }

    private static void applyFlashMode(
        Camera.Parameters parameters,
        String requestedMode
    ) {
        List<String> modes =
            parameters.getSupportedFlashModes();

        if (modes == null || modes.isEmpty()) {
            return;
        }

        String mode = requestedMode;

        if ("torch".equals(mode)) {
            mode = Camera.Parameters.FLASH_MODE_TORCH;
        } else {
            mode = Camera.Parameters.FLASH_MODE_OFF;
        }

        if (modes.contains(mode)) {
            parameters.setFlashMode(mode);
        }
    }

    private static void applyZoom(
        Camera.Parameters parameters,
        double requestedZoom
    ) {
        if (!parameters.isZoomSupported()) {
            return;
        }

        List<Integer> ratios =
            parameters.getZoomRatios();

        if (ratios == null || ratios.isEmpty()) {
            return;
        }

        int requestedRatio =
            (int) Math.round(
                requestedZoom * 100.0
            );

        int bestIndex = 0;
        int bestDistance = Integer.MAX_VALUE;

        for (int index = 0;
             index < ratios.size();
             index++) {
            int distance =
                Math.abs(
                    ratios.get(index)
                        - requestedRatio
                );

            if (distance < bestDistance) {
                bestDistance = distance;
                bestIndex = index;
            }
        }

        parameters.setZoom(bestIndex);
    }

    private static double zoomRatio(
        Camera.Parameters parameters
    ) {
        if (!parameters.isZoomSupported()) {
            return 1.0;
        }

        List<Integer> ratios =
            parameters.getZoomRatios();

        if (ratios == null || ratios.isEmpty()) {
            return 1.0;
        }

        int index =
            Math.max(
                0,
                Math.min(
                    parameters.getZoom(),
                    ratios.size() - 1
                )
            );

        return ratios.get(index) / 100.0;
    }

    private void releasePreviewTexture() {
        SurfaceTexture texture = previewTexture;
        previewTexture = null;

        if (texture != null) {
            try {
                texture.release();
            } catch (RuntimeException ignored) {
            }
        }
    }
}
