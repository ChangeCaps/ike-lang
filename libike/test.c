#include <ike/gc.h>
#include <stdio.h>

int main() {
    int *obj = ike_alloc(sizeof *obj);
    ike_copy(obj);

    if (ike_free(obj)) {
        printf("was freed");
    }

    if (ike_free(obj)) {
        printf("was freed2");
    }
}
