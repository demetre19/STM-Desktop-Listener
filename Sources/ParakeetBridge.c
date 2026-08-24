#include "ParakeetBridge.h"
#include "../Vendor/sherpa-onnx/c-api.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static pthread_mutex_t recognizer_mutex = PTHREAD_MUTEX_INITIALIZER;
static const SherpaOnnxOfflineRecognizer *recognizer = NULL;
static char *recognizer_model_directory = NULL;
static pthread_mutex_t punctuation_mutex = PTHREAD_MUTEX_INITIALIZER;
static const SherpaOnnxOnlinePunctuation *punctuation = NULL;
static char *punctuation_model_directory = NULL;

static char *copy_string(const char *value) {
    if (value == NULL) {
        return NULL;
    }
    size_t length = strlen(value) + 1;
    char *copy = malloc(length);
    if (copy != NULL) {
        memcpy(copy, value, length);
    }
    return copy;
}

static char *path_join(const char *directory, const char *filename) {
    size_t length = strlen(directory) + strlen(filename) + 2;
    char *path = malloc(length);
    if (path != NULL) {
        snprintf(path, length, "%s/%s", directory, filename);
    }
    return path;
}

static void set_error(char **error_message, const char *message) {
    if (error_message != NULL) {
        *error_message = copy_string(message);
    }
}

static void destroy_recognizer_locked(void) {
    if (recognizer != NULL) {
        SherpaOnnxDestroyOfflineRecognizer(recognizer);
        recognizer = NULL;
    }
    free(recognizer_model_directory);
    recognizer_model_directory = NULL;
}

static int ensure_recognizer_locked(const char *model_directory, char **error_message) {
    if (recognizer != NULL && recognizer_model_directory != NULL &&
        strcmp(recognizer_model_directory, model_directory) == 0) {
        return 1;
    }

    destroy_recognizer_locked();

    char *encoder = path_join(model_directory, "encoder.int8.onnx");
    char *decoder = path_join(model_directory, "decoder.int8.onnx");
    char *joiner = path_join(model_directory, "joiner.int8.onnx");
    char *tokens = path_join(model_directory, "tokens.txt");
    if (encoder == NULL || decoder == NULL || joiner == NULL || tokens == NULL) {
        set_error(error_message, "Unable to allocate Parakeet model paths.");
        free(encoder);
        free(decoder);
        free(joiner);
        free(tokens);
        return 0;
    }

    if (access(encoder, R_OK) != 0 || access(decoder, R_OK) != 0 ||
        access(joiner, R_OK) != 0 || access(tokens, R_OK) != 0) {
        set_error(error_message, "The selected Parakeet model folder is incomplete or unreadable.");
        free(encoder);
        free(decoder);
        free(joiner);
        free(tokens);
        return 0;
    }

    SherpaOnnxOfflineRecognizerConfig config;
    memset(&config, 0, sizeof(config));
    config.feat_config.sample_rate = 16000;
    config.feat_config.feature_dim = 80;
    config.model_config.transducer.encoder = encoder;
    config.model_config.transducer.decoder = decoder;
    config.model_config.transducer.joiner = joiner;
    config.model_config.tokens = tokens;
    config.model_config.num_threads = 2;
    config.model_config.provider = "cpu";
    config.model_config.model_type = "nemo_transducer";
    config.decoding_method = "greedy_search";

    recognizer = SherpaOnnxCreateOfflineRecognizer(&config);
    free(encoder);
    free(decoder);
    free(joiner);
    free(tokens);

    if (recognizer == NULL) {
        set_error(error_message, "sherpa-onnx could not load the Parakeet model.");
        return 0;
    }

    recognizer_model_directory = copy_string(model_directory);
    if (recognizer_model_directory == NULL) {
        destroy_recognizer_locked();
        set_error(error_message, "Unable to retain the Parakeet model path.");
        return 0;
    }
    return 1;
}
static void destroy_punctuation_locked(void) {
    if (punctuation != NULL) {
        SherpaOnnxDestroyOnlinePunctuation(punctuation);
        punctuation = NULL;
    }
    free(punctuation_model_directory);
    punctuation_model_directory = NULL;
}

static int ensure_punctuation_locked(const char *model_directory, char **error_message) {
    if (punctuation != NULL && punctuation_model_directory != NULL &&
        strcmp(punctuation_model_directory, model_directory) == 0) {
        return 1;
    }

    destroy_punctuation_locked();

    char *model = path_join(model_directory, "model.int8.onnx");
    char *vocab = path_join(model_directory, "bpe.vocab");
    if (model == NULL || vocab == NULL) {
        set_error(error_message, "Unable to allocate punctuation model paths.");
        free(model);
        free(vocab);
        return 0;
    }
    if (access(model, R_OK) != 0 || access(vocab, R_OK) != 0) {
        set_error(error_message, "The bundled punctuation model is incomplete or unreadable.");
        free(model);
        free(vocab);
        return 0;
    }

    SherpaOnnxOnlinePunctuationConfig config;
    memset(&config, 0, sizeof(config));
    config.model.cnn_bilstm = model;
    config.model.bpe_vocab = vocab;
    config.model.num_threads = 1;
    config.model.provider = "cpu";
    punctuation = SherpaOnnxCreateOnlinePunctuation(&config);
    free(model);
    free(vocab);

    if (punctuation == NULL) {
        set_error(error_message, "sherpa-onnx could not load the punctuation model.");
        return 0;
    }

    punctuation_model_directory = copy_string(model_directory);
    if (punctuation_model_directory == NULL) {
        destroy_punctuation_locked();
        set_error(error_message, "Unable to retain the punctuation model path.");
        return 0;
    }
    return 1;
}

char *STMParakeetTranscribe(const char *model_directory, const char *wave_path, char **error_message) {
    if (error_message != NULL) {
        *error_message = NULL;
    }
    if (model_directory == NULL || wave_path == NULL) {
        set_error(error_message, "A Parakeet model folder and WAV file are required.");
        return NULL;
    }

    pthread_mutex_lock(&recognizer_mutex);
    if (!ensure_recognizer_locked(model_directory, error_message)) {
        pthread_mutex_unlock(&recognizer_mutex);
        return NULL;
    }

    const SherpaOnnxWave *wave = SherpaOnnxReadWave(wave_path);
    if (wave == NULL) {
        set_error(error_message, "Parakeet could not read the recorded WAV file.");
        pthread_mutex_unlock(&recognizer_mutex);
        return NULL;
    }

    const SherpaOnnxOfflineStream *stream = SherpaOnnxCreateOfflineStream(recognizer);
    if (stream == NULL) {
        SherpaOnnxFreeWave(wave);
        set_error(error_message, "Parakeet could not create a transcription stream.");
        pthread_mutex_unlock(&recognizer_mutex);
        return NULL;
    }

    SherpaOnnxAcceptWaveformOffline(stream, wave->sample_rate, wave->samples, wave->num_samples);
    SherpaOnnxDecodeOfflineStream(recognizer, stream);
    const SherpaOnnxOfflineRecognizerResult *result = SherpaOnnxGetOfflineStreamResult(stream);
    char *text = result != NULL ? copy_string(result->text) : NULL;

    if (result != NULL) {
        SherpaOnnxDestroyOfflineRecognizerResult(result);
    }
    SherpaOnnxDestroyOfflineStream(stream);
    SherpaOnnxFreeWave(wave);

    if (text == NULL) {
        set_error(error_message, "Parakeet returned no transcription result.");
    }
    pthread_mutex_unlock(&recognizer_mutex);
    return text;
}
char *STMAddPunctuation(const char *model_directory, const char *text, char **error_message) {
    if (error_message != NULL) {
        *error_message = NULL;
    }
    if (model_directory == NULL || text == NULL) {
        set_error(error_message, "A punctuation model folder and input text are required.");
        return NULL;
    }

    pthread_mutex_lock(&punctuation_mutex);
    if (!ensure_punctuation_locked(model_directory, error_message)) {
        pthread_mutex_unlock(&punctuation_mutex);
        return NULL;
    }

    const char *result = SherpaOnnxOnlinePunctuationAddPunct(punctuation, text);
    if (result == NULL) {
        set_error(error_message, "The punctuation model returned no text.");
        pthread_mutex_unlock(&punctuation_mutex);
        return NULL;
    }
    char *copy = copy_string(result);
    SherpaOnnxOnlinePunctuationFreeText(result);
    if (copy == NULL) {
        set_error(error_message, "Unable to copy the punctuated text.");
    }
    pthread_mutex_unlock(&punctuation_mutex);
    return copy;
}

void STMPunctuationReset(void) {
    pthread_mutex_lock(&punctuation_mutex);
    destroy_punctuation_locked();
    pthread_mutex_unlock(&punctuation_mutex);
}

void STMParakeetReset(void) {
    pthread_mutex_lock(&recognizer_mutex);
    destroy_recognizer_locked();
    pthread_mutex_unlock(&recognizer_mutex);
}

void STMParakeetFreeString(char *value) {
    free(value);
}
