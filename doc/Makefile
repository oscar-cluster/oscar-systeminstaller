DOCBASE = systeminstaller-oscar_manual

pdf: $(DOCBASE).sgml
	dblatex  -o $(DOCBASE).pdf $(DOCBASE).sgml

html: $(DOCBASE).sgml
	sgmltools -b onehtml $(DOCBASE).sgml

all: pdf html

clean:
	rm -f $(DOCBASE).pdf $(DOCBASE).html 
