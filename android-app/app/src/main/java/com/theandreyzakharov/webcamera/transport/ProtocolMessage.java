package com.theandreyzakharov.webcamera.transport;

import android.os.SystemClock;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.concurrent.atomic.AtomicLong;

public final class ProtocolMessage {
    public static final int VERSION = 1;

    private static final AtomicLong sequence =
        new AtomicLong(1);

    private ProtocolMessage() {
    }

    public static JSONObject create(
        String type
    ) throws JSONException {
        JSONObject message = new JSONObject();

        message.put("version", VERSION);
        message.put("type", type);
        message.put(
            "sequence",
            sequence.getAndIncrement()
        );
        message.put(
            "timestamp",
            SystemClock.elapsedRealtime()
        );

        return message;
    }

    public static JSONObject response(
        String type,
        JSONObject request
    ) throws JSONException {
        JSONObject message = create(type);

        if (request != null
            && request.has("sequence")) {
            message.put(
                "relatedSequence",
                request.optLong("sequence")
            );
        }

        return message;
    }

    public static JSONObject error(
        String code,
        String text,
        boolean fatal,
        JSONObject request
    ) {
        try {
            JSONObject message =
                response("error", request);

            message.put("code", code);
            message.put("message", text);
            message.put("fatal", fatal);

            return message;
        } catch (JSONException exception) {
            return new JSONObject();
        }
    }

    public static JSONObject parse(
        String line
    ) throws JSONException {
        JSONObject message =
            new JSONObject(line);

        int version =
            message.optInt("version", -1);

        if (version != VERSION) {
            throw new JSONException(
                "Unsupported protocol version: "
                    + version
            );
        }

        String type =
            message.optString("type", "");

        if (type.length() == 0) {
            throw new JSONException(
                "Message type is missing."
            );
        }

        return message;
    }
}
