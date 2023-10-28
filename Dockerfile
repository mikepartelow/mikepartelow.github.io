FROM ruby
RUN gem install github-pages
COPY mikepartelow.github.io/Gemfile* /tmp
RUN cd /tmp && bundle
RUN apt update && apt install -yq less vim
WORKDIR /mikepartelow.github.io
