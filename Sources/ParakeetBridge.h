#ifndef STM_PARAKEET_BRIDGE_H
#define STM_PARAKEET_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

char *STMParakeetTranscribe(const char *model_directory, const char *wave_path, char **error_message);
char *STMAddPunctuation(const char *model_directory, const char *text, char **error_message);
void STMPunctuationReset(void);
void STMParakeetReset(void);
void STMParakeetFreeString(char *value);

unsigned char *STMWebPEncodeRGBA(
    const unsigned char *rgba,
    int width,
    int height,
    int stride,
    float quality,
    unsigned long *output_size
);
void STMWebPFree(void *value);

#ifdef __cplusplus
}
#endif

#endif
