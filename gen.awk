BEGIN {
    for (i = 1; i <= 12; ++i) {
        printf "case sdl.K_F%d:\n\treturn util.KEY_F%d\n", i, i;
    }
}
