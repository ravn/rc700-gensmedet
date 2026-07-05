#!/usr/bin/env perl
# Rewrite LLVM local/private labels into z80asm-legal identifiers:
#   .LBB0_4  -> LBB0_4     (strip leading dot, internal dots -> _)
#   .L.str   -> L_str
#   L_.str.1 -> L__str_1   (private global, no leading dot)
while (<>) {
    s/\.L([A-Za-z0-9_.]+)/ my $s=$1; $s=~tr:.:_:; "L$s" /ge;
    s/\bL_[A-Za-z0-9_.]+/ my $s=$&; $s=~tr:.:_:; $s /ge;
    print;
}
