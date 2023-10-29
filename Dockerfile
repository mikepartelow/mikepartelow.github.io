FROM ruby
RUN gem install github-pages
COPY docs/Gemfile* /tmp
RUN cd /tmp && bundle
RUN apt update && apt install -yq less vim
WORKDIR /docs
