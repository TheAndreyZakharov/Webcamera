package com.theandreyzakharov.webcamera.transport;

import android.os.Build;
import android.util.Log;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketException;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicBoolean;

public final class ControlServer {
    private static final String TAG =
        "WebcameraControlServer";

    public static final int PORT = 27283;

    public interface Listener {
        JSONObject onControlMessage(
            JSONObject message
        );
    }

    private final Listener listener;

    private final AtomicBoolean running =
        new AtomicBoolean(false);

    private volatile ServerSocket serverSocket;
    private volatile Socket clientSocket;
    private volatile Thread serverThread;
    private volatile BufferedWriter clientWriter;

    public ControlServer(
        Listener listener
    ) {
        this.listener = listener;
    }

    public synchronized void start() {
        if (running.get()) {
            return;
        }

        running.set(true);

        serverThread = new Thread(
            new Runnable() {
                @Override
                public void run() {
                    runServer();
                }
            },
            "WebcameraControlServer"
        );

        serverThread.start();
    }

    public synchronized void stop() {
        running.set(false);

        closeClient();
        closeServer();

        Thread thread = serverThread;
        serverThread = null;

        if (thread != null) {
            thread.interrupt();
        }
    }

    public void send(
        JSONObject message
    ) {
        if (message == null) {
            return;
        }

        BufferedWriter writer = clientWriter;

        if (writer == null) {
            return;
        }

        synchronized (writer) {
            try {
                writer.write(message.toString());
                writer.newLine();
                writer.flush();
            } catch (IOException exception) {
                Log.e(
                    TAG,
                    "Unable to send control message",
                    exception
                );

                closeClient();
            }
        }
    }

    private void runServer() {
        while (running.get()) {
            try {
                ServerSocket newServer =
                    new ServerSocket(
                        PORT,
                        1,
                        InetAddress.getByName("127.0.0.1")
                    );

                newServer.setReuseAddress(true);
                serverSocket = newServer;

                Log.i(
                    TAG,
                    "Control server listening on 127.0.0.1:"
                        + PORT
                );

                while (running.get()) {
                    Socket socket = newServer.accept();

                    socket.setTcpNoDelay(true);
                    socket.setKeepAlive(true);

                    clientSocket = socket;

                    Log.i(
                        TAG,
                        "Control client connected"
                    );

                    try {
                        handleClient(socket);
                    } finally {
                        closeClient();
                    }
                }
            } catch (SocketException exception) {
                if (running.get()) {
                    Log.e(
                        TAG,
                        "Control socket error",
                        exception
                    );
                }
            } catch (IOException exception) {
                if (running.get()) {
                    Log.e(
                        TAG,
                        "Control server error",
                        exception
                    );
                }
            } finally {
                closeClient();
                closeServer();
            }

            if (running.get()) {
                sleepQuietly(500);
            }
        }
    }

    private void handleClient(
        Socket socket
    ) throws IOException {
        BufferedReader reader =
            new BufferedReader(
                new InputStreamReader(
                    socket.getInputStream(),
                    StandardCharsets.UTF_8
                )
            );

        BufferedWriter writer =
            new BufferedWriter(
                new OutputStreamWriter(
                    socket.getOutputStream(),
                    StandardCharsets.UTF_8
                )
            );

        clientWriter = writer;

        send(createHello());

        String line;

        while (running.get()
            && (line = reader.readLine()) != null) {
            if (line.length() > 1024 * 1024) {
                send(
                    ProtocolMessage.error(
                        "message_too_large",
                        "Control message exceeds 1 MiB.",
                        false,
                        null
                    )
                );

                continue;
            }

            try {
                JSONObject request =
                    ProtocolMessage.parse(line);

                JSONObject response =
                    listener.onControlMessage(
                        request
                    );

                if (response != null) {
                    send(response);
                }
            } catch (JSONException exception) {
                send(
                    ProtocolMessage.error(
                        "invalid_message",
                        exception.getMessage(),
                        false,
                        null
                    )
                );
            } catch (RuntimeException exception) {
                send(
                    ProtocolMessage.error(
                        "internal_error",
                        exception.getMessage(),
                        false,
                        null
                    )
                );
            }
        }
    }

    private JSONObject createHello() {
        try {
            JSONObject hello =
                ProtocolMessage.create("hello");

            hello.put(
                "deviceId",
                Build.SERIAL != null
                    ? Build.SERIAL
                    : "unknown"
            );

            hello.put("deviceName", Build.MODEL);
            hello.put("manufacturer", Build.MANUFACTURER);
            hello.put("model", Build.MODEL);
            hello.put(
                "androidVersion",
                Build.VERSION.RELEASE
            );
            hello.put(
                "apiLevel",
                Build.VERSION.SDK_INT
            );
            hello.put(
                "buildDisplay",
                Build.DISPLAY
            );
            hello.put(
                "applicationVersion",
                "0.1.0"
            );

            return hello;
        } catch (JSONException exception) {
            return new JSONObject();
        }
    }

    private void closeClient() {
        clientWriter = null;

        Socket socket = clientSocket;
        clientSocket = null;

        if (socket != null) {
            try {
                socket.close();
            } catch (IOException ignored) {
            }
        }
    }

    private void closeServer() {
        ServerSocket socket = serverSocket;
        serverSocket = null;

        if (socket != null) {
            try {
                socket.close();
            } catch (IOException ignored) {
            }
        }
    }

    private static void sleepQuietly(
        long milliseconds
    ) {
        try {
            Thread.sleep(milliseconds);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
        }
    }
}
