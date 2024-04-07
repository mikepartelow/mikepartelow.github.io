.PHONY: build run
build:
	docker build -t jekyll .
shell: build
	docker run -v `pwd`/docs:/docs -p 4000:4000 -ti jekyll bash
run: build
	docker run -v `pwd`/docs:/docs -p 4000:4000 -ti jekyll bundle exec jekyll serve -H 0.0.0.0
open:
	open http://localhost:4000/
