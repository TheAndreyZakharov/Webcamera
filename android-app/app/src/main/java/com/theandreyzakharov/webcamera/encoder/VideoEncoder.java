package com.theandreyzakharov.webcamera.encoder;

import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaFormat;
import android.media.MediaRecorder;
import android.os.Bundle;
import android.util.Log;

import com.theandreyzakharov.webcamera.transport.VideoServer;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

public final class VideoEncoder {
    private static final String TAG =
        "WebcameraEncoder";

    private static final String VIDEO_MIME =
        "video/avc";

    private static final String AUDIO_MIME =
        "audio/mp4a-latm";

    private static final int AUDIO_SAMPLE_RATE =
        48_000;

    private static final int AUDIO_CHANNEL_COUNT =
        1;

    private static final long CODEC_TIMEOUT_US =
        10_000L;

    private final VideoServer videoServer;

    private final AtomicBoolean running =
        new AtomicBoolean(false);

    private MediaCodec videoCodec;
    private MediaCodec audioCodec;
    private AudioRecord audioRecord;

    private Thread videoDrainThread;
    private Thread audioDrainThread;
    private Thread audioCaptureThread;

    private int width;
    private int height;
    private int frameRate;
    private int videoBitRate;
    private int videoColorFormat;

    private String videoCodecName;

    private long startTimestampNs;

    public VideoEncoder(
        VideoServer videoServer
    ) {
        this.videoServer = videoServer;
    }

    public synchronized void start(
        int requestedWidth,
        int requestedHeight,
        int requestedFrameRate,
        int requestedVideoBitRate,
        boolean audioEnabled,
        int audioBitRate
    ) throws IOException {
        stop();

        startTimestampNs =
            System.nanoTime();

        IOException videoFailure =
            configureVideoEncoder(
                requestedWidth,
                requestedHeight,
                requestedFrameRate,
                requestedVideoBitRate
            );

        if (videoFailure != null) {
            releaseCodec(videoCodec);
            videoCodec = null;

            throw videoFailure;
        }

        boolean audioStarted = false;

        if (audioEnabled) {
            try {
                startAudioEncoder(
                    audioBitRate
                );

                audioStarted =
                    audioCodec != null
                        && audioRecord != null;
                        Log.i(
                            TAG,
                            "Phone audio initialized: "
                                + audioStarted
                                + ", requested="
                                + audioEnabled
                                + ", bitrate="
                                + audioBitRate
                        );
            } catch (Exception exception) {
                Log.e(
                    TAG,
                    "Audio encoder could not start. Continuing with video only.",
                    exception
                );

                releaseCodec(audioCodec);
                audioCodec = null;

                if (audioRecord != null) {
                    try {
                        audioRecord.release();
                    } catch (RuntimeException ignored) {
                    }

                    audioRecord = null;
                }
            }
        }

        running.set(true);

        startVideoDrainThread();

        if (audioStarted) {
            startAudioDrainThread();
            startAudioCaptureThread();
        }

        Log.i(
            TAG,
            "Encoder started: codec="
                + videoCodecName
                + ", size="
                + width
                + "x"
                + height
                + ", fps="
                + frameRate
                + ", bitrate="
                + videoBitRate
                + ", colorFormat="
                + colorFormatName(
                    videoColorFormat
                )
                + " ("
                + videoColorFormat
                + "), audio="
                + audioStarted
        );
    }

    public synchronized void stop() {
        boolean hadEncoder =
            videoCodec != null
                || audioCodec != null
                || audioRecord != null
                || running.get();

        if (!hadEncoder) {
            return;
        }

        running.set(false);

        if (audioRecord != null) {
            try {
                audioRecord.stop();
            } catch (RuntimeException ignored) {
            }
        }

        interruptThread(
            videoDrainThread
        );

        interruptThread(
            audioDrainThread
        );

        interruptThread(
            audioCaptureThread
        );

        joinThread(
            videoDrainThread
        );

        joinThread(
            audioDrainThread
        );

        joinThread(
            audioCaptureThread
        );

        videoDrainThread = null;
        audioDrainThread = null;
        audioCaptureThread = null;

        releaseCodec(
            videoCodec
        );

        releaseCodec(
            audioCodec
        );

        videoCodec = null;
        audioCodec = null;

        if (audioRecord != null) {
            try {
                audioRecord.release();
            } catch (RuntimeException ignored) {
            }

            audioRecord = null;
        }

        videoCodecName = null;

        try {
            videoServer.offerFrame(
                EncodedFrame.endOfStream(
                    elapsedTimestampUs()
                )
            );
        } catch (RuntimeException ignored) {
        }

        Log.i(
            TAG,
            "Encoder stopped"
        );
    }

    public boolean isRunning() {
        return running.get();
    }

    public void queueVideoFrame(
        byte[] nv21Data,
        long timestampNs
    ) {
        MediaCodec codec =
            videoCodec;

        if (!running.get()
            || codec == null
            || nv21Data == null) {
            return;
        }

        int expectedSize =
            width
                * height
                * 3
                / 2;

        if (nv21Data.length < expectedSize) {
            Log.w(
                TAG,
                "Short camera frame: expected="
                    + expectedSize
                    + ", actual="
                    + nv21Data.length
            );

            return;
        }

        try {
            int inputIndex =
                codec.dequeueInputBuffer(
                    0
                );

            if (inputIndex < 0) {
                return;
            }

            ByteBuffer[] inputBuffers =
                codec.getInputBuffers();

            if (inputIndex
                >= inputBuffers.length) {
                return;
            }

            ByteBuffer inputBuffer =
                inputBuffers[inputIndex];

            if (inputBuffer == null) {
                codec.queueInputBuffer(
                    inputIndex,
                    0,
                    0,
                    presentationTimestampUs(
                        timestampNs
                    ),
                    0
                );

                return;
            }

            inputBuffer.clear();

            if (inputBuffer.remaining()
                < expectedSize) {
                Log.e(
                    TAG,
                    "Encoder input buffer is too small: remaining="
                        + inputBuffer.remaining()
                        + ", required="
                        + expectedSize
                );

                codec.queueInputBuffer(
                    inputIndex,
                    0,
                    0,
                    presentationTimestampUs(
                        timestampNs
                    ),
                    0
                );

                return;
            }

            writeCameraFrame(
                nv21Data,
                inputBuffer,
                width,
                height,
                videoColorFormat
            );

            codec.queueInputBuffer(
                inputIndex,
                0,
                expectedSize,
                presentationTimestampUs(
                    timestampNs
                ),
                0
            );
        } catch (RuntimeException exception) {
            if (running.get()) {
                Log.e(
                    TAG,
                    "Unable to queue video frame",
                    exception
                );
            }
        }
    }

    public void requestKeyFrame() {
        MediaCodec codec =
            videoCodec;

        if (codec == null
            || !running.get()) {
            return;
        }

        try {
            Bundle parameters =
                new Bundle();

            parameters.putInt(
                MediaCodec
                    .PARAMETER_KEY_REQUEST_SYNC_FRAME,
                0
            );

            codec.setParameters(
                parameters
            );
        } catch (RuntimeException exception) {
            Log.w(
                TAG,
                "Key-frame request was rejected",
                exception
            );
        }
    }

    private IOException configureVideoEncoder(
        int requestedWidth,
        int requestedHeight,
        int requestedFrameRate,
        int requestedBitRate
    ) {
        List<MediaCodecInfo> encoders =
            findVideoEncoders();

        if (encoders.isEmpty()) {
            return new IOException(
                "No H.264 encoder was found."
            );
        }

        int[] frameRateCandidates =
            uniquePositiveValues(
                requestedFrameRate,
                24,
                20,
                15
            );

        int[] bitRateCandidates =
            uniquePositiveValues(
                requestedBitRate,
                Math.min(
                    requestedBitRate,
                    2_000_000
                ),
                1_500_000,
                1_000_000,
                750_000,
                500_000
            );

        Throwable lastFailure =
            null;

        for (MediaCodecInfo codecInfo
            : encoders) {
            int[] colorFormats =
                supportedInputColorFormats(
                    codecInfo
                );

            Log.i(
                TAG,
                "Trying H.264 encoder "
                    + codecInfo.getName()
                    + ", advertised colors="
                    + Arrays.toString(
                        colorFormats
                    )
            );

            for (int colorFormat
                : colorFormats) {
                for (int candidateFrameRate
                    : frameRateCandidates) {
                    for (int candidateBitRate
                        : bitRateCandidates) {
                        MediaCodec candidateCodec =
                            null;

                        try {
                            Log.i(
                                TAG,
                                "Configuring codec="
                                    + codecInfo.getName()
                                    + ", size="
                                    + requestedWidth
                                    + "x"
                                    + requestedHeight
                                    + ", fps="
                                    + candidateFrameRate
                                    + ", bitrate="
                                    + candidateBitRate
                                    + ", color="
                                    + colorFormatName(
                                        colorFormat
                                    )
                                    + " ("
                                    + colorFormat
                                    + ")"
                            );

                            candidateCodec =
                                MediaCodec
                                    .createByCodecName(
                                        codecInfo
                                            .getName()
                                    );

                            MediaFormat format =
                                MediaFormat
                                    .createVideoFormat(
                                        VIDEO_MIME,
                                        requestedWidth,
                                        requestedHeight
                                    );

                            format.setInteger(
                                MediaFormat
                                    .KEY_COLOR_FORMAT,
                                colorFormat
                            );

                            format.setInteger(
                                MediaFormat
                                    .KEY_BIT_RATE,
                                candidateBitRate
                            );

                            format.setInteger(
                                MediaFormat
                                    .KEY_FRAME_RATE,
                                candidateFrameRate
                            );

                            format.setInteger(
                                MediaFormat
                                    .KEY_I_FRAME_INTERVAL,
                                2
                            );

                            format.setInteger(
                                MediaFormat
                                    .KEY_MAX_INPUT_SIZE,
                                requestedWidth
                                    * requestedHeight
                                    * 3
                                    / 2
                            );

                            candidateCodec.configure(
                                format,
                                null,
                                null,
                                MediaCodec
                                    .CONFIGURE_FLAG_ENCODE
                            );

                            candidateCodec.start();

                            videoCodec =
                                candidateCodec;

                            candidateCodec =
                                null;

                            videoCodecName =
                                codecInfo.getName();

                            width =
                                requestedWidth;

                            height =
                                requestedHeight;

                            frameRate =
                                candidateFrameRate;

                            videoBitRate =
                                candidateBitRate;

                            videoColorFormat =
                                colorFormat;

                            return null;
                        } catch (Throwable exception) {
                            lastFailure =
                                exception;

                            Log.w(
                                TAG,
                                "Encoder configuration rejected: codec="
                                    + codecInfo.getName()
                                    + ", size="
                                    + requestedWidth
                                    + "x"
                                    + requestedHeight
                                    + ", fps="
                                    + candidateFrameRate
                                    + ", bitrate="
                                    + candidateBitRate
                                    + ", color="
                                    + colorFormatName(
                                        colorFormat
                                    )
                                    + " ("
                                    + colorFormat
                                    + ")",
                                exception
                            );
                        } finally {
                            releaseCodec(
                                candidateCodec
                            );
                        }
                    }
                }
            }
        }

        String message =
            "All available H.264 encoder configurations were rejected for "
                + requestedWidth
                + "x"
                + requestedHeight
                + ".";

        if (lastFailure != null
            && lastFailure.getMessage() != null) {
            message +=
                " Last error: "
                    + lastFailure.getMessage();
        }

        return new IOException(
            message,
            lastFailure
        );
    }

    private static List<MediaCodecInfo>
        findVideoEncoders() {
        List<MediaCodecInfo> result =
            new ArrayList<MediaCodecInfo>();

        int codecCount =
            MediaCodecList.getCodecCount();

        for (int index = 0;
             index < codecCount;
             index++) {
            MediaCodecInfo codecInfo;

            try {
                codecInfo =
                    MediaCodecList.getCodecInfoAt(
                        index
                    );
            } catch (RuntimeException exception) {
                continue;
            }

            if (codecInfo == null
                || !codecInfo.isEncoder()) {
                continue;
            }

            String[] types =
                codecInfo.getSupportedTypes();

            if (types == null) {
                continue;
            }

            for (String type : types) {
                if (VIDEO_MIME.equalsIgnoreCase(
                    type
                )) {
                    result.add(
                        codecInfo
                    );

                    break;
                }
            }
        }

        return result;
    }

    private static int[]
        supportedInputColorFormats(
            MediaCodecInfo codecInfo
        ) {
        List<Integer> preferred =
            new ArrayList<Integer>();

        try {
            MediaCodecInfo.CodecCapabilities
                capabilities =
                    codecInfo
                        .getCapabilitiesForType(
                            VIDEO_MIME
                        );

            int[] advertised =
                capabilities.colorFormats;

            if (advertised != null) {
                addColorIfSupported(
                    preferred,
                    advertised,
                    MediaCodecInfo
                        .CodecCapabilities
                        .COLOR_FormatYUV420SemiPlanar
                );

                addColorIfSupported(
                    preferred,
                    advertised,
                    MediaCodecInfo
                        .CodecCapabilities
                        .COLOR_FormatYUV420PackedSemiPlanar
                );

                addColorIfSupported(
                    preferred,
                    advertised,
                    MediaCodecInfo
                        .CodecCapabilities
                        .COLOR_FormatYUV420Planar
                );

                addColorIfSupported(
                    preferred,
                    advertised,
                    MediaCodecInfo
                        .CodecCapabilities
                        .COLOR_FormatYUV420PackedPlanar
                );

                for (int format : advertised) {
                    if (isUsableByteBufferColorFormat(
                        format
                    )
                        && !preferred.contains(
                            format
                        )) {
                        preferred.add(
                            format
                        );
                    }
                }
            }
        } catch (RuntimeException exception) {
            Log.w(
                TAG,
                "Unable to query codec color formats for "
                    + codecInfo.getName(),
                exception
            );
        }

        if (preferred.isEmpty()) {
            preferred.add(
                MediaCodecInfo
                    .CodecCapabilities
                    .COLOR_FormatYUV420SemiPlanar
            );

            preferred.add(
                MediaCodecInfo
                    .CodecCapabilities
                    .COLOR_FormatYUV420Planar
            );
        }

        int[] result =
            new int[preferred.size()];

        for (int index = 0;
             index < preferred.size();
             index++) {
            result[index] =
                preferred.get(index);
        }

        return result;
    }

    private static void addColorIfSupported(
        List<Integer> destination,
        int[] advertised,
        int requested
    ) {
        for (int value : advertised) {
            if (value == requested
                && !destination.contains(
                    requested
                )) {
                destination.add(
                    requested
                );

                return;
            }
        }
    }

    private static boolean
        isUsableByteBufferColorFormat(
            int colorFormat
        ) {
        return colorFormat
            == MediaCodecInfo
                .CodecCapabilities
                .COLOR_FormatYUV420SemiPlanar
            || colorFormat
                == MediaCodecInfo
                    .CodecCapabilities
                    .COLOR_FormatYUV420PackedSemiPlanar
            || colorFormat
                == MediaCodecInfo
                    .CodecCapabilities
                    .COLOR_FormatYUV420Planar
            || colorFormat
                == MediaCodecInfo
                    .CodecCapabilities
                    .COLOR_FormatYUV420PackedPlanar;
    }

    private void startAudioEncoder(
        int requestedAudioBitRate
    ) throws IOException {
        int channelMask =
            AudioFormat.CHANNEL_IN_MONO;

        int encoding =
            AudioFormat.ENCODING_PCM_16BIT;

        int minimumBufferSize =
            AudioRecord.getMinBufferSize(
                AUDIO_SAMPLE_RATE,
                channelMask,
                encoding
            );

        if (minimumBufferSize <= 0) {
            throw new IOException(
                "AudioRecord does not support 48 kHz mono PCM."
            );
        }

        int bufferSize =
            Math.max(
                minimumBufferSize * 4,
                AUDIO_SAMPLE_RATE
            );

        AudioRecord record =
            createAudioRecord(
                MediaRecorder.AudioSource.CAMCORDER,
                bufferSize,
                channelMask,
                encoding
            );

        if (record == null) {
            record =
                createAudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    bufferSize,
                    channelMask,
                    encoding
                );
        }

        if (record == null) {
            throw new IOException(
                "The microphone could not be initialized."
            );
        }

        MediaCodec codec =
            null;

        try {
            codec =
                MediaCodec
                    .createEncoderByType(
                        AUDIO_MIME
                    );

            MediaFormat format =
                MediaFormat
                    .createAudioFormat(
                        AUDIO_MIME,
                        AUDIO_SAMPLE_RATE,
                        AUDIO_CHANNEL_COUNT
                    );

            format.setInteger(
                MediaFormat.KEY_AAC_PROFILE,
                MediaCodecInfo
                    .CodecProfileLevel
                    .AACObjectLC
            );

            format.setInteger(
                MediaFormat.KEY_BIT_RATE,
                Math.max(
                    32_000,
                    requestedAudioBitRate
                )
            );

            format.setInteger(
                MediaFormat.KEY_MAX_INPUT_SIZE,
                bufferSize
            );

            codec.configure(
                format,
                null,
                null,
                MediaCodec.CONFIGURE_FLAG_ENCODE
            );

            codec.start();

            audioRecord =
                record;

            audioCodec =
                codec;
        } catch (Exception exception) {
            releaseCodec(
                codec
            );

            try {
                record.release();
            } catch (RuntimeException ignored) {
            }

            if (exception
                instanceof IOException) {
                throw (IOException) exception;
            }

            throw new IOException(
                "AAC encoder could not start: "
                    + exception.getMessage(),
                exception
            );
        }
    }

    private static AudioRecord createAudioRecord(
        int source,
        int bufferSize,
        int channelMask,
        int encoding
    ) {
        AudioRecord record =
            null;

        try {
            record =
                new AudioRecord(
                    source,
                    AUDIO_SAMPLE_RATE,
                    channelMask,
                    encoding,
                    bufferSize
                );

            if (record.getState()
                == AudioRecord
                    .STATE_INITIALIZED) {
                return record;
            }
        } catch (RuntimeException exception) {
            Log.w(
                TAG,
                "AudioRecord source "
                    + source
                    + " failed",
                exception
            );
        }

        if (record != null) {
            try {
                record.release();
            } catch (RuntimeException ignored) {
            }
        }

        return null;
    }

    private void startVideoDrainThread() {
        videoDrainThread =
            new Thread(
                new Runnable() {
                    @Override
                    public void run() {
                        drainVideo();
                    }
                },
                "WebcameraVideoDrain"
            );

        videoDrainThread.start();
    }

    private void startAudioDrainThread() {
        audioDrainThread =
            new Thread(
                new Runnable() {
                    @Override
                    public void run() {
                        drainAudio();
                    }
                },
                "WebcameraAudioDrain"
            );

        audioDrainThread.start();
    }

    private void startAudioCaptureThread() {
        audioCaptureThread =
            new Thread(
                new Runnable() {
                    @Override
                    public void run() {
                        captureAudio();
                    }
                },
                "WebcameraAudioCapture"
            );

        audioCaptureThread.start();
    }

    private void drainVideo() {
        MediaCodec codec =
            videoCodec;

        if (codec == null) {
            return;
        }

        MediaCodec.BufferInfo info =
            new MediaCodec.BufferInfo();

        ByteBuffer[] outputBuffers =
            codec.getOutputBuffers();

        while (running.get()) {
            int outputIndex;

            try {
                outputIndex =
                    codec.dequeueOutputBuffer(
                        info,
                        CODEC_TIMEOUT_US
                    );
            } catch (RuntimeException exception) {
                if (running.get()) {
                    Log.e(
                        TAG,
                        "Video encoder output failed",
                        exception
                    );
                }

                return;
            }

            if (outputIndex
                == MediaCodec
                    .INFO_TRY_AGAIN_LATER) {
                continue;
            }

            if (outputIndex
                == MediaCodec
                    .INFO_OUTPUT_BUFFERS_CHANGED) {
                outputBuffers =
                    codec.getOutputBuffers();

                continue;
            }

            if (outputIndex
                == MediaCodec
                    .INFO_OUTPUT_FORMAT_CHANGED) {
                MediaFormat outputFormat =
                    codec.getOutputFormat();

                Log.i(
                    TAG,
                    "Video output format changed: "
                        + outputFormat
                );

                sendCodecConfiguration(
                    outputFormat,
                    true
                );

                continue;
            }

            if (outputIndex < 0) {
                continue;
            }

            try {
                ByteBuffer outputBuffer =
                    outputBuffers[outputIndex];

                if (outputBuffer == null) {
                    continue;
                }

                outputBuffer.position(
                    info.offset
                );

                outputBuffer.limit(
                    info.offset
                        + info.size
                );

                byte[] data =
                    new byte[info.size];

                outputBuffer.get(
                    data
                );

                boolean codecConfiguration =
                    (info.flags
                        & MediaCodec
                            .BUFFER_FLAG_CODEC_CONFIG)
                        != 0;

                boolean keyFrame =
                    (info.flags
                        & MediaCodec
                            .BUFFER_FLAG_SYNC_FRAME)
                        != 0;

                int flags = 0;

                if (codecConfiguration) {
                    flags |=
                        EncodedFrame
                            .FLAG_CODEC_CONFIGURATION;
                }

                if (keyFrame) {
                    flags |=
                        EncodedFrame
                            .FLAG_KEY_FRAME;
                }

                videoServer.offerFrame(
                    new EncodedFrame(
                        codecConfiguration
                            ? EncodedFrame
                                .TYPE_VIDEO_CONFIGURATION
                            : EncodedFrame
                                .TYPE_VIDEO_FRAME,
                        flags,
                        info.presentationTimeUs,
                        info.presentationTimeUs,
                        data
                    )
                );
            } catch (RuntimeException exception) {
                if (running.get()) {
                    Log.e(
                        TAG,
                        "Unable to process encoded video frame",
                        exception
                    );
                }
            } finally {
                try {
                    codec.releaseOutputBuffer(
                        outputIndex,
                        false
                    );
                } catch (RuntimeException ignored) {
                }
            }
        }
    }

    private void drainAudio() {
        MediaCodec codec =
            audioCodec;

        if (codec == null) {
            return;
        }

        Log.i(
            TAG,
            "AAC drain thread started"
        );

        MediaCodec.BufferInfo info =
            new MediaCodec.BufferInfo();

        ByteBuffer[] outputBuffers =
            codec.getOutputBuffers();

        while (running.get()) {
            int outputIndex;

            try {
                outputIndex =
                    codec.dequeueOutputBuffer(
                        info,
                        CODEC_TIMEOUT_US
                    );
            } catch (RuntimeException exception) {
                if (running.get()) {
                    Log.e(
                        TAG,
                        "Audio encoder output failed",
                        exception
                    );
                }

                return;
            }

            if (outputIndex
                == MediaCodec
                    .INFO_TRY_AGAIN_LATER) {
                continue;
            }

            if (outputIndex
                == MediaCodec
                    .INFO_OUTPUT_BUFFERS_CHANGED) {
                outputBuffers =
                    codec.getOutputBuffers();

                continue;
            }

            if (outputIndex
                == MediaCodec
                    .INFO_OUTPUT_FORMAT_CHANGED) {
                MediaFormat outputFormat =
                    codec.getOutputFormat();

                Log.i(
                    TAG,
                    "Audio output format changed: "
                        + outputFormat
                );

                sendCodecConfiguration(
                    outputFormat,
                    false
                );

                continue;
            }

            if (outputIndex < 0) {
                continue;
            }

            try {
                ByteBuffer outputBuffer =
                    outputBuffers[outputIndex];

                if (outputBuffer == null) {
                    continue;
                }

                outputBuffer.position(
                    info.offset
                );

                outputBuffer.limit(
                    info.offset
                        + info.size
                );

                byte[] data =
                    new byte[info.size];

                outputBuffer.get(
                    data
                );

                boolean codecConfiguration =
                    (info.flags
                        & MediaCodec
                            .BUFFER_FLAG_CODEC_CONFIG)
                        != 0;

                int flags =
                    codecConfiguration
                        ? EncodedFrame
                            .FLAG_CODEC_CONFIGURATION
                        : 0;

                videoServer.offerFrame(
                    new EncodedFrame(
                        codecConfiguration
                            ? EncodedFrame
                                .TYPE_AUDIO_CONFIGURATION
                            : EncodedFrame
                                .TYPE_AUDIO_FRAME,
                        flags,
                        info.presentationTimeUs,
                        info.presentationTimeUs,
                        data
                    )
                );
            } catch (RuntimeException exception) {
                if (running.get()) {
                    Log.e(
                        TAG,
                        "Unable to process encoded audio frame",
                        exception
                    );
                }
            } finally {
                try {
                    codec.releaseOutputBuffer(
                        outputIndex,
                        false
                    );
                } catch (RuntimeException ignored) {
                }
            }
        }
    }

    private void captureAudio() {
        AudioRecord record =
            audioRecord;

        MediaCodec codec =
            audioCodec;

        if (record == null
            || codec == null) {
            return;
        }

        try {
            record.startRecording();
        } catch (RuntimeException exception) {
            Log.e(
                TAG,
                "Unable to start microphone capture",
                exception
            );

            return;
        }

        Log.i(
            TAG,
            "Phone microphone recording started"
        );

        ByteBuffer[] inputBuffers =
            codec.getInputBuffers();

        byte[] temporaryBuffer =
            new byte[4096];

        while (running.get()) {
            int inputIndex;

            try {
                inputIndex =
                    codec.dequeueInputBuffer(
                        CODEC_TIMEOUT_US
                    );
            } catch (RuntimeException exception) {
                return;
            }

            if (inputIndex < 0) {
                continue;
            }

            int bytesRead;

            try {
                bytesRead =
                    record.read(
                        temporaryBuffer,
                        0,
                        temporaryBuffer.length
                    );
            } catch (RuntimeException exception) {
                Log.e(
                    TAG,
                    "Microphone read failed",
                    exception
                );

                return;
            }

            if (bytesRead <= 0) {
                try {
                    codec.queueInputBuffer(
                        inputIndex,
                        0,
                        0,
                        elapsedTimestampUs(),
                        0
                    );
                } catch (RuntimeException ignored) {
                }

                continue;
            }

            ByteBuffer inputBuffer =
                inputBuffers[inputIndex];

            if (inputBuffer == null) {
                continue;
            }

            inputBuffer.clear();

            int copyLength =
                Math.min(
                    bytesRead,
                    inputBuffer.remaining()
                );

            inputBuffer.put(
                temporaryBuffer,
                0,
                copyLength
            );

            try {
                codec.queueInputBuffer(
                    inputIndex,
                    0,
                    copyLength,
                    elapsedTimestampUs(),
                    0
                );
            } catch (RuntimeException exception) {
                if (running.get()) {
                    Log.e(
                        TAG,
                        "Unable to queue audio data",
                        exception
                    );
                }

                return;
            }
        }
    }

    private void sendCodecConfiguration(
        MediaFormat format,
        boolean video
    ) {
        ByteArrayOutputStream stream =
            new ByteArrayOutputStream();

        for (int index = 0;
             index < 4;
             index++) {
            ByteBuffer csd;

            try {
                csd =
                    format.getByteBuffer(
                        "csd-" + index
                    );
            } catch (RuntimeException exception) {
                csd = null;
            }

            if (csd == null) {
                continue;
            }

            ByteBuffer copy =
                csd.duplicate();

            byte[] bytes =
                new byte[
                    copy.remaining()
                ];

            copy.get(
                bytes
            );

            stream.write(
                bytes,
                0,
                bytes.length
            );
        }

        byte[] data =
            stream.toByteArray();

        if (data.length == 0) {
            return;
        }

        long timestamp =
            elapsedTimestampUs();

        videoServer.offerFrame(
            new EncodedFrame(
                video
                    ? EncodedFrame
                        .TYPE_VIDEO_CONFIGURATION
                    : EncodedFrame
                        .TYPE_AUDIO_CONFIGURATION,
                EncodedFrame
                    .FLAG_CODEC_CONFIGURATION,
                timestamp,
                timestamp,
                data
            )
        );
    }

    private long presentationTimestampUs(
        long timestampNs
    ) {
        return Math.max(
            0,
            (
                timestampNs
                    - startTimestampNs
            ) / 1000L
        );
    }

    private long elapsedTimestampUs() {
        return presentationTimestampUs(
            System.nanoTime()
        );
    }

    private static void writeCameraFrame(
        byte[] sourceNv21,
        ByteBuffer destination,
        int width,
        int height,
        int colorFormat
    ) {
        if (colorFormat
            == MediaCodecInfo
                .CodecCapabilities
                .COLOR_FormatYUV420Planar
            || colorFormat
                == MediaCodecInfo
                    .CodecCapabilities
                    .COLOR_FormatYUV420PackedPlanar) {
            putNv21AsI420(
                sourceNv21,
                destination,
                width,
                height
            );

            return;
        }

        putNv21AsNv12(
            sourceNv21,
            destination,
            width,
            height
        );
    }

    private static void putNv21AsNv12(
        byte[] source,
        ByteBuffer destination,
        int width,
        int height
    ) {
        int ySize =
            width * height;

        int totalSize =
            ySize * 3 / 2;

        destination.put(
            source,
            0,
            ySize
        );

        for (int index = ySize;
             index + 1 < totalSize;
             index += 2) {
            byte v =
                source[index];

            byte u =
                source[index + 1];

            destination.put(
                u
            );

            destination.put(
                v
            );
        }
    }

    private static void putNv21AsI420(
        byte[] source,
        ByteBuffer destination,
        int width,
        int height
    ) {
        int ySize =
            width * height;

        int chromaSize =
            ySize / 4;

        int totalSize =
            ySize * 3 / 2;

        destination.put(
            source,
            0,
            ySize
        );

        for (int index = ySize + 1;
             index < totalSize;
             index += 2) {
            destination.put(
                source[index]
            );
        }

        for (int index = ySize;
             index < totalSize;
             index += 2) {
            destination.put(
                source[index]
            );
        }

        int expectedPosition =
            ySize
                + chromaSize
                + chromaSize;

        if (destination.position()
            != expectedPosition) {
            throw new IllegalStateException(
                "Invalid I420 conversion size: "
                    + destination.position()
                    + " instead of "
                    + expectedPosition
            );
        }
    }

    private static int[] uniquePositiveValues(
        int... values
    ) {
        List<Integer> result =
            new ArrayList<Integer>();

        for (int value : values) {
            if (value > 0
                && !result.contains(
                    value
                )) {
                result.add(
                    value
                );
            }
        }

        int[] array =
            new int[result.size()];

        for (int index = 0;
             index < result.size();
             index++) {
            array[index] =
                result.get(index);
        }

        return array;
    }

    private static String colorFormatName(
        int format
    ) {
        if (format
            == MediaCodecInfo
                .CodecCapabilities
                .COLOR_FormatYUV420SemiPlanar) {
            return "YUV420SemiPlanar/NV12";
        }

        if (format
            == MediaCodecInfo
                .CodecCapabilities
                .COLOR_FormatYUV420PackedSemiPlanar) {
            return "YUV420PackedSemiPlanar";
        }

        if (format
            == MediaCodecInfo
                .CodecCapabilities
                .COLOR_FormatYUV420Planar) {
            return "YUV420Planar/I420";
        }

        if (format
            == MediaCodecInfo
                .CodecCapabilities
                .COLOR_FormatYUV420PackedPlanar) {
            return "YUV420PackedPlanar";
        }

        return "Unknown";
    }

    private static void releaseCodec(
        MediaCodec codec
    ) {
        if (codec == null) {
            return;
        }

        try {
            codec.stop();
        } catch (RuntimeException ignored) {
        }

        try {
            codec.release();
        } catch (RuntimeException ignored) {
        }
    }

    private static void interruptThread(
        Thread thread
    ) {
        if (thread != null) {
            thread.interrupt();
        }
    }

    private static void joinThread(
        Thread thread
    ) {
        if (thread == null
            || thread
                == Thread.currentThread()) {
            return;
        }

        try {
            thread.join(
                1500
            );
        } catch (InterruptedException exception) {
            Thread.currentThread()
                .interrupt();
        }
    }
}
