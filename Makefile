WORDSOURCE ?= classic

all: wordos.com

wordlist.inc: wordlist.py
	python3 wordlist.py $(WORDSOURCE)

wordos.com: wordos.asm wordlist.inc
	yasm -fbin -o$@ -lwordos.lst $<

test: wordos.com
	dosbox $<

clean:
	rm -f wordos.com wordos.lst wordlist.inc

distclean: clean
	rm -f yasm.exe

.PHONY: all test clean distclean
