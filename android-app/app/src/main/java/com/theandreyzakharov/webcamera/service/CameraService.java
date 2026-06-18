package com.theandreyzakharov.webcamera.service;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

import com.theandreyzakharov.webcamera.R;
import com.theandreyzakharov.webcamera.camera.CameraCapabilities;
import com.theandreyzakharov.webcamera.camera.CameraConfiguration;
import com.theandreyzakharov.webcamera.camera.CameraController;
import com.theandreyzakharov.webcamera.encoder.VideoEncoder;
import com.theandreyzakharov.webcamera.transport.ControlServer;
import com.theandreyzakharov.webcamera.transport.ProtocolMessage;
import com.theandreyzakharov.webcamera.transport.VideoServer;
import com.theandreyzakharov.webcamera.ui.MainActivity;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class CameraService extends Service
    implements ControlServer.Listener {

    private static final String TAG =
        "WebcameraService";

    private static final String CHANNEL_ID =
        "webcamera_capture";

    private static final int NOTIFICATION_ID = 27283;

    public static final String ACTION_START_SERVICE =
        "com.theandreyzakharov.webcamera.START_SERVICE";

    public static final String ACTION_START_STREAM =
        "com.theandreyzakharov.webcamera.START_STREAM";

    public static final String ACTION_STOP_STREAM =
        "com.theandreyzakharov.webcamera.STOP_STREAM";

    public static final String ACTION_TOGGLE_TORCH =
        "com.theandreyzakharov.webcamera.TOGGLE_TORCH";

    public static final String ACTION_STATUS =
        "com.theandreyzakharov.webcamera.STATUS";

    public static final String EXTRA_STATUS =
        "status";

    private final ExecutorService commandExecutor =
        Executors.newSingleThreadExecutor();

    private VideoServer videoServer;
    private ControlServer controlServer;
    private VideoEncoder encoder;
    private CameraController cameraController;

    private volatile CameraConfiguration configuration =
        CameraConfiguration.defaults();

    private volatile String state = "idle";
    private volatile String lastError = "";

    @Override
    public void onCreate() {
        super.onCreate();

        createNotificationChannel();
        startForeground(
            NOTIFICATION_ID,
            createNotification("Waiting for Mac")
        );

        videoServer = new VideoServer();
        encoder = new VideoEncoder(videoServer);
        cameraController =
            new CameraController(encoder);

        controlServer =
            new ControlServer(this);

        videoServer.start();
        controlServer.start();

        updateState("idle", "");
    }

    @Override
    public int onStartCommand(
        Intent intent,
        int flags,
        int startId
    ) {
        String action =
            intent != null
                ? intent.getAction()
                : null;

        if (ACTION_START_STREAM.equals(action)) {
            commandExecutor.execute(
                new Runnable() {
                    @Override
                    public void run() {
                        startStreaming();
                    }
                }
            );
        } else if (ACTION_STOP_STREAM.equals(action)) {
            commandExecutor.execute(
                new Runnable() {
                    @Override
                    public void run() {
                        stopStreaming();
                    }
                }
            );
        } else if (ACTION_TOGGLE_TORCH.equals(action)) {
            commandExecutor.execute(
                new Runnable() {
                    @Override
                    public void run() {
                        boolean enabled =
                            !cameraController
                                .isTorchEnabled();

                        setTorch(enabled);
                    }
                }
            );
        }

        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        stopStreaming();

        if (controlServer != null) {
            controlServer.stop();
        }

        if (videoServer != null) {
            videoServer.stop();
        }

        commandExecutor.shutdownNow();

        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public JSONObject onControlMessage(
        final JSONObject message
    ) {
        String type =
            message.optString("type", "");

        try {
            if ("getCapabilities".equals(type)) {
                JSONObject response =
                    ProtocolMessage.response(
                        "capabilities",
                        message
                    );

                JSONObject capabilities =
                    CameraCapabilities
                        .discover()
                        .toJson();

                copyJson(capabilities, response);

                return response;
            }

            if ("configure".equals(type)) {
                if (cameraController.isStreaming()) {
                    return ProtocolMessage.error(
                        "invalid_state",
                        "Stop streaming before configuration.",
                        false,
                        message
                    );
                }

                configuration =
                    CameraConfiguration.fromJson(
                        message,
                        configuration
                    );

                cameraController.configure(
                    configuration
                );

                JSONObject response =
                    ProtocolMessage.response(
                        "configured",
                        message
                    );

                copyJson(
                    configuration.toJson(),
                    response
                );

                return response;
            }

            if ("start".equals(type)) {
                commandExecutor.execute(
                    new Runnable() {
                        @Override
                        public void run() {
                            startStreaming();
                        }
                    }
                );

                JSONObject response =
                    ProtocolMessage.response(
                        "status",
                        message
                    );

                response.put("state", "starting");

                return response;
            }

            if ("stop".equals(type)) {
                commandExecutor.execute(
                    new Runnable() {
                        @Override
                        public void run() {
                            stopStreaming();
                        }
                    }
                );

                JSONObject response =
                    ProtocolMessage.response(
                        "status",
                        message
                    );

                response.put("state", "stopping");

                return response;
            }

            if ("setFlashMode".equals(type)) {
                String flashMode =
                    message.optString(
                        "flashMode",
                        "off"
                    );

                boolean enabled =
                    "torch".equals(flashMode)
                        || "on".equals(flashMode);

                boolean success =
                    setTorch(enabled);

                JSONObject response =
                    ProtocolMessage.response(
                        "flashStatus",
                        message
                    );

                response.put(
                    "requestedMode",
                    flashMode
                );

                response.put(
                    "appliedMode",
                    cameraController
                        .isTorchEnabled()
                        ? "torch"
                        : "off"
                );

                response.put(
                    "available",
                    success
                        || cameraController.isStreaming()
                );

                if (!success) {
                    response.put(
                        "message",
                        cameraController.isStreaming()
                            ? "The active camera rejected torch mode."
                            : "Start the rear camera before enabling the torch."
                    );
                }

                return response;
            }

            if ("setZoom".equals(type)) {
                double requestedZoom =
                    message.optDouble(
                        "zoom",
                        1.0
                    );

                boolean success =
                    cameraController.setZoom(
                        requestedZoom
                    );

                JSONObject response =
                    ProtocolMessage.response(
                        "zoomChanged",
                        message
                    );

                response.put(
                    "requestedZoom",
                    requestedZoom
                );

                response.put(
                    "appliedZoom",
                    cameraController
                        .getConfiguration()
                        .zoom
                );

                response.put("success", success);

                return response;
            }

            if ("requestKeyFrame".equals(type)) {
                cameraController.requestKeyFrame();

                return ProtocolMessage.response(
                    "keyFrameRequested",
                    message
                );
            }

            if ("ping".equals(type)) {
                JSONObject response =
                    ProtocolMessage.response(
                        "pong",
                        message
                    );

                response.put(
                    "nonce",
                    message.opt("nonce")
                );

                return response;
            }

            if ("getStatus".equals(type)) {
                return createStatusMessage(message);
            }

            return ProtocolMessage.error(
                "unsupported_command",
                "Unsupported command: " + type,
                false,
                message
            );
        } catch (JSONException exception) {
            return ProtocolMessage.error(
                "internal_error",
                exception.getMessage(),
                false,
                message
            );
        }
    }

    private void startStreaming() {
        if (cameraController.isStreaming()) {
            updateState("streaming", "");
            return;
        }

        if (!hasCameraPermission()) {
            updateState(
                "failed",
                "Camera permission is not granted."
            );

            sendError(
                "camera_permission_denied",
                "Camera permission is not granted."
            );

            return;
        }

        if (configuration.audioEnabled
            && !hasAudioPermission()) {
            updateState(
                "failed",
                "Microphone permission is not granted."
            );

            sendError(
                "microphone_permission_denied",
                "Microphone permission is not granted."
            );

            return;
        }

        updateState("starting", "");

        try {
            cameraController.configure(
                configuration
            );

            cameraController.start();

            configuration =
                cameraController.getConfiguration();

            updateState("streaming", "");
            sendStatus();
        } catch (IOException exception) {
            Log.e(
                TAG,
                "Unable to start streaming",
                exception
            );

            updateState(
                "failed",
                exception.getMessage()
            );

            sendError(
                "camera_open_failed",
                exception.getMessage()
            );
        }
    }

    private void stopStreaming() {
        if (cameraController != null) {
            cameraController.stop();
        }

        updateState("idle", "");
        sendStatus();
    }

    private boolean setTorch(
        boolean enabled
    ) {
        boolean result =
            cameraController != null
                && cameraController
                    .setTorchEnabled(enabled);

        sendStatus();

        return result;
    }

    private JSONObject createStatusMessage(
        JSONObject request
    ) {
        try {
            JSONObject status =
                ProtocolMessage.response(
                    "status",
                    request
                );

            status.put("state", state);
            status.put(
                "streaming",
                cameraController != null
                    && cameraController
                        .isStreaming()
            );
            status.put(
                "videoClientConnected",
                videoServer != null
                    && videoServer.hasClient()
            );
            status.put(
                "torchEnabled",
                cameraController != null
                    && cameraController
                        .isTorchEnabled()
            );
            status.put(
                "foregroundServiceActive",
                true
            );
            status.put("message", lastError);

            copyJson(
                configuration.toJson(),
                status
            );

            return status;
        } catch (JSONException exception) {
            return new JSONObject();
        }
    }

    private void sendStatus() {
        if (controlServer != null) {
            controlServer.send(
                createStatusMessage(null)
            );
        }
    }

    private void sendError(
        String code,
        String message
    ) {
        if (controlServer != null) {
            controlServer.send(
                ProtocolMessage.error(
                    code,
                    message,
                    false,
                    null
                )
            );
        }
    }

    private void updateState(
        String newState,
        String error
    ) {
        state = newState;
        lastError = error != null ? error : "";

        NotificationManager manager =
            (NotificationManager) getSystemService(
                NOTIFICATION_SERVICE
            );

        if (manager != null) {
            manager.notify(
                NOTIFICATION_ID,
                createNotification(
                    notificationText()
                )
            );
        }

        Intent statusIntent =
            new Intent(ACTION_STATUS);

        statusIntent.setPackage(
            getPackageName()
        );

        statusIntent.putExtra(
            EXTRA_STATUS,
            notificationText()
        );

        sendBroadcast(statusIntent);
    }

    private String notificationText() {
        if ("streaming".equals(state)) {
            return cameraController != null
                && cameraController
                    .isTorchEnabled()
                ? "Streaming camera, audio and torch"
                : "Streaming camera and audio";
        }

        if ("failed".equals(state)) {
            return lastError.length() > 0
                ? lastError
                : "Streaming failed";
        }

        if ("starting".equals(state)) {
            return "Starting camera";
        }

        return "Waiting for Mac connection";
    }

    private Notification createNotification(
        String text
    ) {
        Intent activityIntent =
            new Intent(
                this,
                MainActivity.class
            );

        int pendingIntentFlags =
            PendingIntent.FLAG_UPDATE_CURRENT;

        if (Build.VERSION.SDK_INT >= 23) {
            pendingIntentFlags |=
                PendingIntent.FLAG_IMMUTABLE;
        }

        PendingIntent pendingIntent =
            PendingIntent.getActivity(
                this,
                0,
                activityIntent,
                pendingIntentFlags
            );

        Notification.Builder builder =
            Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(
                    this,
                    CHANNEL_ID
                )
                : new Notification.Builder(this);

        builder
            .setContentTitle("Webcamera")
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true);

        return builder.build();
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT < 26) {
            return;
        }

        NotificationChannel channel =
            new NotificationChannel(
                CHANNEL_ID,
                "Webcamera capture",
                NotificationManager
                    .IMPORTANCE_LOW
            );

        channel.setDescription(
            "Camera and microphone streaming status"
        );

        NotificationManager manager =
            (NotificationManager) getSystemService(
                NOTIFICATION_SERVICE
            );

        if (manager != null) {
            manager.createNotificationChannel(
                channel
            );
        }
    }

    private boolean hasCameraPermission() {
        return checkCallingOrSelfPermission(
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED;
    }

    private boolean hasAudioPermission() {
        return checkCallingOrSelfPermission(
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED;
    }

    private static void copyJson(
        JSONObject source,
        JSONObject destination
    ) throws JSONException {
        java.util.Iterator<String> keys =
            source.keys();

        while (keys.hasNext()) {
            String key = keys.next();

            destination.put(
                key,
                source.get(key)
            );
        }
    }
}
