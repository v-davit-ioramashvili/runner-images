#include <stdio.h>
int main() {
    int n, i, flag = 0;
    scanf("%d", &n);
    for (i = 2; i <= n / 2; ++i) {
        if (n % i == 0) { flag = 1; break; }
    }
    printf(flag ? "%d is not a prime number.\n" : "%d is a prime number.\n", n);
    return 0;
}
