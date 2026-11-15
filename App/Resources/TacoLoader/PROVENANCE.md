# Taco loader source

45 original PNG frames and manifest copied byte-for-byte from
Fiestaboard/fiestaboard-tvos at d98a0f6d09392ec4273830f64a5d497afe8edc58,
Resources/TacoLoader. Animation source: taco-hop.gif, 1.92s, final frame160ms.
App/Parity/TacoLoader.swift ports Sources/UI/TacoLoader.swift from that revision,
adding only the 14pt inline size. I2 freezes the first frame; production users
can animate, respecting Reduce Motion and scene activity.

Taco artwork © FiestaBoard. All rights reserved. Used in this app with permission.
The artwork is not MIT licensed. See ThirdPartyNotices/FiestaBoardTV-MIT.txt.
