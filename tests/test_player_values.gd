class_name TestPlayerValues
extends RefCounted
## The player values a test pack declares, as a game's own pack would: the
## engine's sanity, arousal and morale roles, played by humanity, libido and
## morale, with libido allowed up to 110 during fights.

const TEXT := """== values player
values:
    humanity: number 100 (0 to 100)
        role: sanity
    libido: number 0 (0 to 100, up to 110 in fights)
        role: arousal
    morale: number 0
        role: morale
    lust: number 0
"""
