package com.theandreyzakharov.webcamera.encoder;

public final class EncodedFrame {
    public static final int TYPE_VIDEO_CONFIGURATION = 1;
    public static final int TYPE_VIDEO_FRAME = 2;
    public static final int TYPE_AUDIO_CONFIGURATION = 3;
    public static final int TYPE_AUDIO_FRAME = 4;
    public static final int TYPE_END_OF_STREAM = 5;

    public static final int FLAG_KEY_FRAME = 0x0001;
    public static final int FLAG_CODEC_CONFIGURATION = 0x0002;
    public static final int FLAG_END_OF_STREAM = 0x0004;
    public static final int FLAG_DISCONTINUITY = 0x0008;

    public final int packetType;
    public final int flags;
    public final long presentationTimestampUs;
    public final long decodingTimestampUs;
    public final byte[] data;

    public EncodedFrame(
        int packetType,
        int flags,
        long presentationTimestampUs,
        long decodingTimestampUs,
        byte[] data
    ) {
        this.packetType = packetType;
        this.flags = flags;
        this.presentationTimestampUs =
            presentationTimestampUs;
        this.decodingTimestampUs =
            decodingTimestampUs;
        this.data = data != null ? data : new byte[0];
    }

    public static EncodedFrame endOfStream(
        long timestampUs
    ) {
        return new EncodedFrame(
            TYPE_END_OF_STREAM,
            FLAG_END_OF_STREAM,
            timestampUs,
            timestampUs,
            new byte[0]
        );
    }
}
