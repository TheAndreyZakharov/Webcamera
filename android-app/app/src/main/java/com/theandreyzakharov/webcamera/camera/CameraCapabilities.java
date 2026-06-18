package com.theandreyzakharov.webcamera.camera;

import android.hardware.Camera;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

@SuppressWarnings("deprecation")
public final class CameraCapabilities {
    private final JSONArray cameras;

    private CameraCapabilities(JSONArray cameras) {
        this.cameras = cameras;
    }

    public static CameraCapabilities discover() {
        JSONArray result = new JSONArray();

        int cameraCount;

        try {
            cameraCount = Camera.getNumberOfCameras();
        } catch (RuntimeException exception) {
            cameraCount = 0;
        }

        for (int cameraId = 0; cameraId < cameraCount; cameraId++) {
            Camera camera = null;

            try {
                Camera.CameraInfo cameraInfo = new Camera.CameraInfo();
                Camera.getCameraInfo(cameraId, cameraInfo);

                camera = Camera.open(cameraId);

                if (camera == null) {
                    continue;
                }

                Camera.Parameters parameters = camera.getParameters();

                JSONObject cameraObject = new JSONObject();
                cameraObject.put("id", String.valueOf(cameraId));
                cameraObject.put(
                    "name",
                    cameraInfo.facing == Camera.CameraInfo.CAMERA_FACING_FRONT
                        ? "Front camera"
                        : "Rear camera"
                );
                cameraObject.put(
                    "facing",
                    cameraInfo.facing == Camera.CameraInfo.CAMERA_FACING_FRONT
                        ? "front"
                        : "rear"
                );
                cameraObject.put(
                    "sensorOrientation",
                    cameraInfo.orientation
                );

                List<String> flashModes =
                    parameters.getSupportedFlashModes();

                boolean flashAvailable =
                    flashModes != null
                        && !flashModes.isEmpty();

                boolean torchAvailable =
                    flashModes != null
                        && flashModes.contains(
                            Camera.Parameters.FLASH_MODE_TORCH
                        );

                cameraObject.put(
                    "flashAvailable",
                    flashAvailable
                );

                cameraObject.put(
                    "torchAvailable",
                    torchAvailable
                );

                cameraObject.put(
                    "zoomSupported",
                    parameters.isZoomSupported()
                );

                cameraObject.put(
                    "minimumZoom",
                    1.0
                );

                cameraObject.put(
                    "maximumZoom",
                    maximumZoomRatio(parameters)
                );

                cameraObject.put(
                    "zoomRatios",
                    zoomRatios(parameters)
                );

                cameraObject.put(
                    "focusModes",
                    stringArray(
                        parameters.getSupportedFocusModes()
                    )
                );

                cameraObject.put(
                    "flashModes",
                    stringArray(flashModes)
                );

                cameraObject.put(
                    "formats",
                    discoverFormats(parameters)
                );

                result.put(cameraObject);
            } catch (Exception ignored) {
                // Одна проблемная камера не должна ломать обнаружение остальных.
            } finally {
                if (camera != null) {
                    try {
                        camera.release();
                    } catch (RuntimeException ignored) {
                    }
                }
            }
        }

        return new CameraCapabilities(result);
    }

    public JSONArray getCameras() {
        return cameras;
    }

    public JSONObject toJson() throws JSONException {
        JSONObject root = new JSONObject();
        root.put("cameras", cameras);

        JSONArray encoders = new JSONArray();

        JSONObject videoEncoder = new JSONObject();
        videoEncoder.put("mimeType", "video/avc");
        videoEncoder.put("name", "Android MediaCodec H.264");
        videoEncoder.put("hardwareAccelerated", true);
        encoders.put(videoEncoder);

        JSONObject audioEncoder = new JSONObject();
        audioEncoder.put("mimeType", "audio/mp4a-latm");
        audioEncoder.put("name", "Android MediaCodec AAC");
        audioEncoder.put("hardwareAccelerated", true);
        encoders.put(audioEncoder);

        root.put("encoders", encoders);

        JSONObject defaults = new JSONObject();
        defaults.put("cameraId", preferredCameraId());
        defaults.put("width", 1280);
        defaults.put("height", 720);
        defaults.put("frameRate", 30);
        defaults.put("bitRate", 4_000_000);
        defaults.put("audioEnabled", true);
        defaults.put("audioBitRate", 128_000);
        defaults.put("flashMode", "off");

        root.put("defaultConfiguration", defaults);

        return root;
    }

    private String preferredCameraId() {
        for (int index = 0; index < cameras.length(); index++) {
            JSONObject camera = cameras.optJSONObject(index);

            if (camera != null
                && "rear".equals(camera.optString("facing"))) {
                return camera.optString("id", "0");
            }
        }

        if (cameras.length() > 0) {
            JSONObject first = cameras.optJSONObject(0);

            if (first != null) {
                return first.optString("id", "0");
            }
        }

        return "0";
    }

    private static JSONArray discoverFormats(
        Camera.Parameters parameters
    ) throws JSONException {
        JSONArray formats = new JSONArray();

        List<Camera.Size> sizes =
            new ArrayList<>(
                parameters.getSupportedPreviewSizes()
            );

        Collections.sort(
            sizes,
            new Comparator<Camera.Size>() {
                @Override
                public int compare(
                    Camera.Size first,
                    Camera.Size second
                ) {
                    long firstPixels =
                        (long) first.width * first.height;

                    long secondPixels =
                        (long) second.width * second.height;

                    return Long.compare(
                        secondPixels,
                        firstPixels
                    );
                }
            }
        );

        List<int[]> ranges =
            parameters.getSupportedPreviewFpsRange();

        for (Camera.Size size : sizes) {
            JSONObject format = new JSONObject();

            format.put("width", size.width);
            format.put("height", size.height);

            JSONArray frameRates = new JSONArray();

            if (ranges != null) {
                for (int[] range : ranges) {
                    if (range == null || range.length < 2) {
                        continue;
                    }

                    int minimum = range[0] / 1000;
                    int maximum = range[1] / 1000;

                    JSONObject frameRateRange =
                        new JSONObject();

                    frameRateRange.put("minimum", minimum);
                    frameRateRange.put("maximum", maximum);

                    frameRates.put(frameRateRange);
                }
            }

            if (frameRates.length() == 0) {
                JSONObject fallback = new JSONObject();
                fallback.put("minimum", 15);
                fallback.put("maximum", 30);
                frameRates.put(fallback);
            }

            format.put("frameRates", frameRates);
            formats.put(format);
        }

        return formats;
    }

    private static JSONArray stringArray(
        List<String> values
    ) {
        JSONArray array = new JSONArray();

        if (values == null) {
            return array;
        }

        for (String value : values) {
            array.put(value);
        }

        return array;
    }

    private static JSONArray zoomRatios(
        Camera.Parameters parameters
    ) throws JSONException {
        JSONArray array = new JSONArray();

        if (!parameters.isZoomSupported()) {
            array.put(1.0);
            return array;
        }

        List<Integer> ratios =
            parameters.getZoomRatios();

        if (ratios == null || ratios.isEmpty()) {
            array.put(1.0);
            return array;
        }

        for (Integer ratio : ratios) {
            if (ratio != null) {
                array.put(ratio / 100.0);
            }
        }

        return array;
    }

    private static double maximumZoomRatio(
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

        return ratios.get(ratios.size() - 1) / 100.0;
    }
}
