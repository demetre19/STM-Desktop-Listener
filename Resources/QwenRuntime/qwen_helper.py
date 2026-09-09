#!/usr/bin/env python3
import contextlib
import json
import os
import sys
import tempfile
import traceback
import time
import uuid

MAX_AUDIO_BYTES = 512 * 1024 * 1024


def emit(payload):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def fail(request_id, message):
    emit({"id": request_id, "ok": False, "error": message})


def validated_wav_path(value):
    if not isinstance(value, str) or not value:
        raise ValueError("A WAV path is required.")
    path = os.path.realpath(value)
    if not path.lower().endswith(".wav") or not os.path.isfile(path):
        raise ValueError("The transcription input must be a readable WAV file.")
    size = os.path.getsize(path)
    if size <= 44 or size > MAX_AUDIO_BYTES:
        raise ValueError("The WAV file size is invalid.")
    with open(path, "rb") as stream:
        header = stream.read(12)
    if len(header) != 12 or header[:4] != b"RIFF" or header[8:] != b"WAVE":
        raise ValueError("The transcription input is not a valid WAV file.")
    return path


def main():
    if len(sys.argv) != 2:
        emit({"type": "fatal", "error": "Pass the local Qwen3-ASR model directory."})
        return 2

    model_path = os.path.realpath(sys.argv[1])
    if not os.path.isdir(model_path):
        emit({"type": "fatal", "error": "The Qwen3-ASR model directory is unavailable."})
        return 2

    try:
        with contextlib.redirect_stdout(sys.stderr):
            from mlx_audio.stt.generate import generate_transcription
            from mlx_audio.stt.utils import load_model
            model = load_model(model_path)
        emit({"type": "ready"})
    except Exception:
        traceback.print_exc(file=sys.stderr)
        emit({"type": "fatal", "error": "Qwen3-ASR could not load the installed model."})
        return 1

    for raw_line in sys.stdin:
        request_id = None
        try:
            request = json.loads(raw_line)
            request_id = request.get("id")
            operation = request.get("op")
            if operation == "shutdown":
                emit({"id": request_id, "ok": True})
                return 0
            if operation != "transcribe":
                raise ValueError("Unsupported Qwen3-ASR helper operation.")

            started = time.monotonic()
            wav_path = validated_wav_path(request.get("path"))
            output_stem = os.path.join(tempfile.gettempdir(), "stm-qwen-" + uuid.uuid4().hex)
            output_path = output_stem + ".txt"
            try:
                with contextlib.redirect_stdout(sys.stderr):
                    result = generate_transcription(
                        model=model,
                        audio=wav_path,
                        output_path=output_stem,
                        format="txt",
                        verbose=False,
                    )
                text = result.text.strip()
            finally:
                try:
                    os.remove(output_path)
                except FileNotFoundError:
                    pass

            if not text:
                raise RuntimeError("Qwen3-ASR returned an empty transcript.")
            emit({
                "id": request_id,
                "ok": True,
                "text": text,
                "elapsedMilliseconds": int((time.monotonic() - started) * 1000),
            })
        except Exception as error:
            traceback.print_exc(file=sys.stderr)
            fail(request_id, str(error) or "Qwen3-ASR transcription failed.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
