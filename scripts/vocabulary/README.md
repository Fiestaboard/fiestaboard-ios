Ported from fiestaboard-tvos f1fc67d. `draft-baseline.json` tracks exact existing
copy, not approved vocabulary. Remove entries as each Phase 5 surface is rebuilt;
do not add new copy to the baseline. I0b prevents new violations without rewriting
all UI ahead of I6–I25. Run the positive/negative control with test-vocabulary.mjs.

Snapshot recording and regression checks require the I2 parity foundation; I0b
uploads an explicit pending report, never a fabricated parity pass or golden.
