#!/usr/bin/env python3
import urllib.request
import sys
import re

def gd2jdn(y, m, d):
    "pseudo-JDN algorithm as used in WorDOS"
    y -= 1968
    z = (y - 1) if (m < 3) else y
    if m < 3: m += 12
    f = (979 * m - 2918) >> 5
    return d + f + 365 * z + (z >> 2)

if __name__ == "__main__":
    args = [a.lower() for a in sys.argv[1:]]
    if "nyt" in args:
        KeyDate = 2022, 2, 26
        KeyWord = "spill"
        ScriptURL = "https://www.nytimes.com/games/wordle/main.4d41d2be.js"
    elif "classic" in args:
        KeyDate = 2022, 2, 26
        KeyWord = "bloke"
        ScriptURL = "http://web.archive.org/web/20220201092205js_/https://www.powerlanguage.co.uk/wordle/main.e65ce0a5.js"
    else:
        assert 0, "please specify data source ('nyt' or 'classic')"

    with urllib.request.urlopen(ScriptURL) as f:
        data = f.read().decode('utf-8', 'replace')
    wordlists = []
    for stringlist in re.findall(r'\[([a-z",]+)\]', data):
        stringlist = [s[1:-1] for s in stringlist.split(',') if s.startswith('"') and s.endswith('"')]
        if stringlist and (set(map(len, stringlist)) == {5}):
            wordlists.append(stringlist)
    assert len(wordlists) == 2
    challenge, verify = sorted(wordlists, key=len)
    words = challenge + verify
    adjust = gd2jdn(*KeyDate) - challenge.index(KeyWord)

    with open("wordlist.inc", "w") as f:
        f.write(f"%define CHALLENGE_WORDS {len(challenge):5d}\n")
        f.write(f"%define VERIFY_WORDS    {len(verify):5d}\n")
        f.write(f"%define TOTAL_WORDS     {len(words):5d}\n")
        f.write(f"%define DATE_ADJUST     {adjust:5d}\n")
        f.write("\nwordsource:\n")
        f.write("    db 'This program contains the word list from the following URL:', 13,10\n")
        f.write(f"    db '{ScriptURL}', 13,10\n")
        f.write("    db 13,10, '$'\n")
        f.write("\nwords:\n")
        for word in words:
            # note: the encoding is a slightly peculiar "middle-endian" thimg,
            # chosen to fit well with the 2+1-byte structure

            # encoder
            a,b,c,d,e = [ord(k) - 97 for k in word]
            xy = a + 26 * (b + 26 *c)
            zz = d + 26 * e
            xy += (zz >> 8) * 26 * 26 * 26
            assert xy <= 0xFFFF
            z = zz & 0xFF
            x = xy & 0xFF
            y = xy >> 8
            f.write(f"    db {x:03X}h, {y:03X}h, {z:03X}h  ; {word}\n")

            # decoder (just for verification)
            xy = x | (y << 8)
            a = xy % 26;  xy //= 26
            b = xy % 26;  xy //= 26
            c = xy % 26;  xy //= 26
            xy = (xy << 8) | z
            d = xy % 26;  xy //= 26
            e = xy % 26;  xy //= 26
            assert xy == 0

            # identity check
            recon = ''.join(chr(k + 97) for k in (a,b,c,d,e))
            assert recon == word
        f.write("endwords:\n")
