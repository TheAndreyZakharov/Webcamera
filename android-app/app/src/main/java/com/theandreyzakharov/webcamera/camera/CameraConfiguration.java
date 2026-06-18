package com.theandreyzakharov.webcamera.camera;

import org.json.JSONException;
import org.json.JSONObject;

public final class CameraConfiguration {
    public final int cameraId;
    public final int width;
    public final int height;
    public final int frameRate;
    public final int videoBitRate;
    public final boolean audioEnabled;
    public final int audioBitRate;
    public final String focusMode;
    public final String flashMode;
    public final double zoom;

    public CameraConfiguration(
        int cameraId,
        int width,
        int height,
        int frameRate,
        int videoBitRate,
        boolean audioEnabled,
        int audioBitRate,
        String focusMode,
        String flashMode,
        double zoom
    ) {
        this.cameraId = cameraId;
        this.width = width;
        this.height = height;
        this.frameRate = frameRate;
        this.videoBitRate = videoBitRate;
        this.audioEnabled = audioEnabled;
        this.audioBitRate = audioBitRate;
        this.focusMode = focusMode;
        this.flashMode = flashMode;
        this.zoom = zoom;
    }

    public static CameraConfiguration defaults() {
        return new CameraConfiguration(
            0,
            1280,
            720,
            30,
            4_000_000,
            true,
            128_000,
            "continuous-video",
            "off",
            1.0
        );
    }

    public static CameraConfiguration fromJson(
        JSONObject json,
        CameraConfiguration fallback
    ) {
        if (fallback == null) {
            fallback = defaults();
        }

        return new CameraConfiguration(
            parseCameraId(
                json.optString(
                    "cameraId",
                    String.valueOf(fallback.cameraId)
                ),
                fallback.cameraId
            ),
            positive(
                json.optInt("width", fallback.width),
                fallback.width
            ),
            positive(
                json.optInt("height", fallback.height),
                fallback.height
            ),
            clamp(
                json.optInt(
                    "frameRate",
                    fallback.frameRate
                ),
                1,
                120
            ),
            clamp(
                json.optInt(
                    "bitRate",
                    fallback.videoBitRate
                ),
                250_000,
                50_000_000
            ),
            json.optBoolean(
                "audioEnabled",
                fallback.audioEnabled
            ),
            clamp(
                json.optInt(
                    "audioBitRate",
                    fallback.audioBitRate
                ),
                32_000,
                320_000
            ),
            json.optString(
                "focusMode",
                fallback.focusMode
            ),
            json.optString(
                "flashMode",
                fallback.flashMode
            ),
            Math.max(
                1.0,
                json.optDouble(
                    "zoom",
                    fallback.zoom
                )
            )
        );
    }

    public JSONObject toJson() throws JSONException {
        JSONObject json = new JSONObject();

        json.put("cameraId", String.valueOf(cameraId));
        json.put("width", width);
        json.put("height", height);
        json.put("frameRate", frameRate);
        json.put("bitRate", videoBitRate);
        json.put("audioEnabled", audioEnabled);
        json.put("audioBitRate", audioBitRate);
        json.put("focusMode", focusMode);
        json.put("flashMode", flashMode);
        json.put("zoom", zoom);

        return json;
    }

    public CameraConfiguration withFlashMode(
        String newFlashMode
    ) {
        return new CameraConfiguration(
            cameraId,
            width,
            height,
            frameRate,
            videoBitRate,
            audioEnabled,
            audioBitRate,
            focusMode,
            newFlashMode,
            zoom
        );
    }

    public CameraConfiguration withZoom(
        double newZoom
    ) {
        return new CameraConfiguration(
            cameraId,
            width,
            height,
            frameRate,
            videoBitRate,
            audioEnabled,
            audioBitRate,
            focusMode,
            flashMode,
            newZoom
        );
    }

    private static int parseCameraId(
        String value,
        int fallback
    ) {
        try {
            return Integer.parseInt(value);
        } catch (NumberFormatException ignored) {
            return fallback;
        }
    }

    private static int positive(
        int value,
        int fallback
    ) {
        return value > 0 ? value : fallback;
    }

    private static int clamp(
        int value,
        int minimum,
        int maximum
    ) {
        return Math.max(
            minimum,
            Math.min(maximum, value)
        );
    }
}
