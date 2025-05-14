#!/bin/bash
set -e
# for mdfile in *.md; do
#   texfile=${mdfile%.md}.tex
#   pdffile=${mdfile%.md}.pdf
#     echo $mdfile
#     pandoc -t beamer --standalone --listings --pdf-engine=xelatex --slide-level=2 --biblatex --csl=citstyle.csl --filter=pandoc-citeproc $mdfile -o $texfile
#     latexmk -pdf $texfile
#    latexmk -c $texfile
#done


echo $1
pandoc -f markdown+fancy_lists-simple_tables -t beamer --template eisvogel.latex --standalone --listings --pdf-engine=xelatex --slide-level=2 --biblatex --csl=citstyle.csl $1.md -o $1.tex
latexmk -pdf  $1.tex
