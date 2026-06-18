package com.theandreyzakharov.webcamera.transport;

import android.util.Log;

import com.theandreyzakharov.webcamera.encoder.EncodedFrame;

import java.io.BufferedOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketException;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

public final class VideoServer {
    private static final String TAG = "WebcameraVideoServer";

    public static final int PORT = 27284;

    private static final int MAX_QUEUE_SIZE = 180;

    private final BlockingQueue<EncodedFrame> frameQueue =
        new ArrayBlockingQueue<>(MAX_QUEUE_SIZE);

    private final AtomicBoolean running =
        new AtomicBoolean(false);

    private final AtomicLong sequence =
        new AtomicLong(0);

    private volatile ServerSocket serverSocket;
    private volatile Socket clientSocket;
    private volatile Thread serverThread;

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
            "WebcameraVideoServer"
        );

        serverThread.start();
    }

    public synchronized void stop() {
        running.set(false);
        frameQueue.clear();

        closeClient();
        closeServer();

        Thread thread = serverThread;
        serverThread = null;

        if (thread != null) {
            thread.interrupt();
        }
    }

    public boolean hasClient() {
        Socket socket = clientSocket;

        return socket != null
            && socket.isConnected()
            && !socket.isClosed();
    }

    public void offerFrame(
        EncodedFrame frame
    ) {
        if (frame == null || !running.get()) {
            return;
        }

        if (!frameQueue.offer(frame)) {
            frameQueue.poll();
            frameQueue.offer(frame);
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
                    "Video server listening on 127.0.0.1:" + PORT
                );

                while (running.get()) {
                    Socket socket = newServer.accept();

                    socket.setTcpNoDelay(true);
                    socket.setKeepAlive(true);

                    clientSocket = socket;
                    frameQueue.clear();
                    sequence.set(0);

                    Log.i(TAG, "Video client connected");

                    try {
                        writeFrames(socket);
                    } finally {
                        closeClient();
                        frameQueue.clear();
                    }
                }
            } catch (SocketException exception) {
                if (running.get()) {
                    Log.e(
                        TAG,
                        "Video server socket error",
                        exception
                    );
                }
            } catch (IOException exception) {
                if (running.get()) {
                    Log.e(
                        TAG,
                        "Video server error",
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

    private void writeFrames(
        Socket socket
    ) throws IOException {
        DataOutputStream output =
            new DataOutputStream(
                new BufferedOutputStream(
                    socket.getOutputStream(),
                    256 * 1024
                )
            );

        while (running.get() && !socket.isClosed()) {
            EncodedFrame frame;

            try {
                frame = frameQueue.poll(
                    1,
                    TimeUnit.SECONDS
                );
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
                return;
            }

            if (frame == null) {
                continue;
            }

            writePacket(output, frame);
            output.flush();
        }
    }

    private void writePacket(
        DataOutputStream output,
        EncodedFrame frame
    ) throws IOException {
        output.writeByte(0x57);
        output.writeByte(0x42);
        output.writeByte(0x43);
        output.writeByte(0x4D);

        output.writeByte(1);
        output.writeByte(frame.packetType);
        output.writeShort(frame.flags);

        output.writeLong(
            sequence.getAndIncrement()
        );

        output.writeLong(
            frame.presentationTimestampUs
        );

        output.writeLong(
            frame.decodingTimestampUs
        );

        output.writeInt(frame.data.length);
        output.write(frame.data);
    }

    private void closeClient() {
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
