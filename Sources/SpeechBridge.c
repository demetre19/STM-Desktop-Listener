#include "SpeechBridge.h"
#include "../Vendor/sherpa-onnx/c-api.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

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


void STMFreeString(char *value) {
    free(value);
}
