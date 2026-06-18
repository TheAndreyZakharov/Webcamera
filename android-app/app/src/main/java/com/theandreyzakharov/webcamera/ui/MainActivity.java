package com.theandreyzakharov.webcamera.ui;

import android.Manifest;
import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import com.theandreyzakharov.webcamera.service.CameraService;

public final class MainActivity extends Activity {
    private static final int PERMISSION_REQUEST = 1001;

    private TextView statusText;

    private final BroadcastReceiver statusReceiver =
        new BroadcastReceiver() {
            @Override
            public void onReceive(
                Context context,
                Intent intent
            ) {
                if (intent == null) {
                    return;
                }

                String status =
                    intent.getStringExtra(
                        CameraService.EXTRA_STATUS
                    );

                if (status != null) {
                    setStatus(status);
                }
            }
        };

    @Override
    protected void onCreate(
        Bundle savedInstanceState
    ) {
        super.onCreate(savedInstanceState);

        setContentView(createContentView());

        requestRequiredPermissions();
        startCameraService();

        setStatus(
            "Waiting for permission and Mac connection"
        );
    }

    @Override
    protected void onResume() {
        super.onResume();

        IntentFilter filter =
            new IntentFilter(
                CameraService.ACTION_STATUS
            );

        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(
                statusReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED
            );
        } else {
            registerReceiver(
                statusReceiver,
                filter
            );
        }
    }

    @Override
    protected void onPause() {
        try {
            unregisterReceiver(statusReceiver);
        } catch (IllegalArgumentException ignored) {
        }

        super.onPause();
    }

    @Override
    public void onRequestPermissionsResult(
        int requestCode,
        String[] permissions,
        int[] grantResults
    ) {
        super.onRequestPermissionsResult(
            requestCode,
            permissions,
            grantResults
        );

        if (requestCode == PERMISSION_REQUEST) {
            if (hasRequiredPermissions()) {
                setStatus(
                    "Ready. Connect from the Mac or press Start Stream."
                );

                startCameraService();
            } else {
                setStatus(
                    "Camera and microphone permissions are required."
                );
            }
        }
    }

    private View createContentView() {
        ScrollView scrollView =
            new ScrollView(this);

        LinearLayout content =
            new LinearLayout(this);

        content.setOrientation(
            LinearLayout.VERTICAL
        );

        content.setGravity(
            Gravity.CENTER_HORIZONTAL
        );

        int padding = dp(24);

        content.setPadding(
            padding,
            padding,
            padding,
            padding
        );

        TextView title =
            new TextView(this);

        title.setText("Webcamera");
        title.setTextSize(28);
        title.setTextColor(Color.WHITE);
        title.setGravity(Gravity.CENTER);

        content.addView(
            title,
            matchWrap()
        );

        TextView description =
            new TextView(this);

        description.setText(
            "USB camera source for the Webcamera macOS application.\n\n"
                + "Video: H.264\n"
                + "Audio: AAC mono\n"
                + "Control: ADB over USB\n"
                + "Control port: 27283\n"
                + "Media port: 27284"
        );

        description.setTextSize(16);
        description.setTextColor(
            Color.LTGRAY
        );

        description.setGravity(
            Gravity.CENTER
        );

        LinearLayout.LayoutParams descriptionParams =
            matchWrap();

        descriptionParams.topMargin = dp(24);

        content.addView(
            description,
            descriptionParams
        );

        statusText = new TextView(this);
        statusText.setTextSize(16);
        statusText.setTextColor(
            Color.rgb(120, 220, 140)
        );
        statusText.setGravity(Gravity.CENTER);
        statusText.setPadding(
            dp(12),
            dp(20),
            dp(12),
            dp(20)
        );

        content.addView(
            statusText,
            matchWrap()
        );

        Button startButton =
            new Button(this);

        startButton.setText("Start Stream");

        startButton.setOnClickListener(
            new View.OnClickListener() {
                @Override
                public void onClick(View view) {
                    if (!hasRequiredPermissions()) {
                        requestRequiredPermissions();
                        return;
                    }

                    sendServiceAction(
                        CameraService
                            .ACTION_START_STREAM
                    );

                    setStatus("Starting stream");
                }
            }
        );

        content.addView(
            startButton,
            buttonParams()
        );

        Button stopButton =
            new Button(this);

        stopButton.setText("Stop Stream");

        stopButton.setOnClickListener(
            new View.OnClickListener() {
                @Override
                public void onClick(View view) {
                    sendServiceAction(
                        CameraService
                            .ACTION_STOP_STREAM
                    );

                    setStatus("Stopping stream");
                }
            }
        );

        content.addView(
            stopButton,
            buttonParams()
        );

        Button torchButton =
            new Button(this);

        torchButton.setText("Toggle Torch");

        torchButton.setOnClickListener(
            new View.OnClickListener() {
                @Override
                public void onClick(View view) {
                    sendServiceAction(
                        CameraService
                            .ACTION_TOGGLE_TORCH
                    );
                }
            }
        );

        content.addView(
            torchButton,
            buttonParams()
        );

        TextView warning =
            new TextView(this);

        warning.setText(
            "Keep the phone connected by USB with USB debugging enabled. "
                + "The Mac connects through ADB forwarding. "
                + "The application does not require Wi-Fi."
        );

        warning.setTextColor(Color.GRAY);
        warning.setTextSize(14);
        warning.setGravity(Gravity.CENTER);

        LinearLayout.LayoutParams warningParams =
            matchWrap();

        warningParams.topMargin = dp(24);

        content.addView(
            warning,
            warningParams
        );

        content.setBackgroundColor(
            Color.rgb(20, 22, 25)
        );

        scrollView.addView(content);

        return scrollView;
    }

    private void startCameraService() {
        Intent intent =
            new Intent(
                this,
                CameraService.class
            );

        intent.setAction(
            CameraService.ACTION_START_SERVICE
        );

        if (Build.VERSION.SDK_INT >= 26) {
            startForegroundService(intent);
        } else {
            startService(intent);
        }
    }

    private void sendServiceAction(
        String action
    ) {
        Intent intent =
            new Intent(
                this,
                CameraService.class
            );

        intent.setAction(action);

        if (Build.VERSION.SDK_INT >= 26) {
            startForegroundService(intent);
        } else {
            startService(intent);
        }
    }

    private void requestRequiredPermissions() {
        if (hasRequiredPermissions()) {
            return;
        }

        if (Build.VERSION.SDK_INT >= 23) {
            requestPermissions(
                new String[] {
                    Manifest.permission.CAMERA,
                    Manifest.permission.RECORD_AUDIO
                },
                PERMISSION_REQUEST
            );
        }
    }

    private boolean hasRequiredPermissions() {
        if (Build.VERSION.SDK_INT < 23) {
            return true;
        }

        return checkSelfPermission(
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
            && checkSelfPermission(
                Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED;
    }

    private void setStatus(
        String status
    ) {
        if (statusText != null) {
            statusText.setText(status);
        }
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        );
    }

    private LinearLayout.LayoutParams buttonParams() {
        LinearLayout.LayoutParams params =
            matchWrap();

        params.topMargin = dp(10);

        return params;
    }

    private int dp(
        int value
    ) {
        return Math.round(
            value
                * getResources()
                    .getDisplayMetrics()
                    .density
        );
    }
}
