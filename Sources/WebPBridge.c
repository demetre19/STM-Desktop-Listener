#include <stddef.h>
#include <stdint.h>

extern size_t WebPEncodeRGBA(
    const uint8_t *rgba,
    int width,
    int height,
    int stride,
    float quality_factor,
    uint8_t **output
);
extern void WebPFree(void *ptr);

uint8_t *STMWebPEncodeRGBA(
    const uint8_t *rgba,
    int width,
    int height,
    int stride,
    float quality,
    size_t *output_size
) {
    if (rgba == NULL || output_size == NULL || width <= 0 || height <= 0 || stride < width * 4) {
        return NULL;
    }

    uint8_t *output = NULL;
    *output_size = WebPEncodeRGBA(rgba, width, height, stride, quality, &output);
    return *output_size == 0 ? NULL : output;
}

void STMWebPFree(void *value) {
    WebPFree(value);
}
