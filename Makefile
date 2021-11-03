spec.pdf : spec.md images/*
	pandoc --standalone --output=spec.pdf spec.md
