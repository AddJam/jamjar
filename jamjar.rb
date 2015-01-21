# Jam Jar - Rails template used by Add Jam
# https://github.com/addjam/jamjar
unless Rails::VERSION::MAJOR >= 4
  raise "spawnpoint was built for rails 4 and up, please update your rails version"
end

# Gemfile & Gems
remove_file "Gemfile"
file "Gemfile", <<-RUBY

source "https://rubygems.org"

gem "rails", "4.2.0"
gem 'turbolinks'
gem 'uglifier'
gem "pg"

gem "sass", "~> 3.4.9"
gem "sass-rails"
gem "bourbon"
gem 'neat'
gem "jquery-rails"
gem "coffee-rails"

gem "puma"

group :development do
  gem "foreman", require: false
  gem "spring"
  gem "quiet_assets"
  gem "better_errors"
  gem 'annotate', require: false
  gem 'byebug'
end

group :development, :test do
  gem "factory_girl_rails"
  gem "rspec-rails", "~> 3.1.0"
  gem "dotenv-rails"
end

group :test do
  gem "shoulda-matchers", "~> 2.7.0", require: false
  gem "timecop"
  gem "database_cleaner"
end

group :production, :staging do
  gem "rails_12factor"
  gem 'therubyracer'
  gem "skylight"
end
RUBY

# Ember-rails? - Inspired by ember-rails edge_template.rb
db_name = ask("What should we call the database?")
use_ember = yes?("Use ember-rails?")
use_auth = yes?("Add user authentication with Devise?")
use_docker = yes?("Set up with docker? Make sure the docker service is currently available if yes.")
if use_docker
  domain = ask("Ok, what domain name should we configure the nginx container with? (example.com)")
  domain = "example.com" if !domain or domain.length == 0
  docker_tag = ask("And what should the docker image be tagged as? (e.g. addjam/web)")
  docker_tag = "addjam/web" if !docker_tag or docker_tag.length == 0
  docker_tag.downcase!
end

if use_ember
  gem "active_model_serializers"
  gem 'ember-rails'
  gem 'ember-source', '~> 1.9.0'
else
  remove_file "app/assets/javascripts/application.js"
  file "app/assets/javascripts/application.js.coffee", <<-COFFEESCRIPT
  #= require jquery
  #= require jquery_ujs
  #= require self
  COFFEESCRIPT
end

if use_auth
  gem "devise"
end

# Bundle
run "bundle install"

# Finish setup of gems
if use_ember
  remove_file "app/assets/javascripts/application.js"
  # Generate a default serializer that is compatible with ember-data
  generate :serializer, "application", "--parent", "ActiveModel::Serializer"
  inject_into_class "app/serializers/application_serializer.rb", 'ApplicationSerializer' do
    "  embed :ids, :include => true\n"
  end

  generate "ember:bootstrap -g --javascript-engine coffee"
  rake "tmp:clear"

  file 'app/assets/javascripts/templates/index.js.handlebars', <<-CODE
  <div style="width: 600px; border: 6px solid #eee; margin: 0 auto; padding: 20px; text-align: center; font-family: sans-serif;">
    <img src="http://emberjs.com/images/about/ember-productivity-sm.png" style="display: block; margin: 0 auto;">
    <h1>Welcome to Ember.js!</h1>
    <p>You're running an Ember.js app on top of Ruby on Rails. To get started, replace this content
    (inside <code>app/assets/javascripts/templates/index.js.handlebars</code>) with your application's
    HTML.</p>
  </div>
  CODE

  # Configure the app to serve Ember.js and app assets from an AssetsController
  generate :controller, "Assets", "index"
  run "rm app/views/assets/index.html.erb"
  file 'app/views/assets/index.html.erb', <<-CODE
  <!DOCTYPE html>
  <html>
  <head>
    <title>#{@app_name.titleize}</title>
    <%= stylesheet_link_tag    "application", :media => "all" %>
    <%= csrf_meta_tags %>
  </head>
  <body>
    <%= javascript_include_tag "application" %>
  </body>
  </html>
  CODE

  run "rm -rf app/views/layouts"
  route "root :to => 'assets#index'"
end

# Rspec
generate "rspec:install"
remove_dir "test"
insert_into_file "spec/rails_helper.rb", "\nrequire 'shoulda/matchers'",
                 after: "require 'rspec/rails'"

# DB Cleaner
file "spec/support/database_cleaner.rb", <<-DBCLEANER
RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end
 
  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
  end
 
  config.before(:each, js: true) do
    DatabaseCleaner.strategy = :truncation
  end
 
  config.before(:each) do
    DatabaseCleaner.start
  end
 
  config.after(:each) do
    DatabaseCleaner.clean
  end
end
DBCLEANER

# Default CSS
remove_file "app/assets/stylesheets/application.css"
file "app/assets/stylesheets/_variables.scss", <<-SCSS
// Put reusable variables here e.g. standard colours
SCSS

file "app/assets/stylesheets/application.scss", <<-SCSS
@import "bourbon";
@import "neat";
@import "variables";
SCSS

# Dotenv & configuration files
env = <<-SHELL
SECRET_KEY_BASE=#{SecureRandom.hex(32)}
DATABASE_HOST=localhost
DATABASE_POOL_SIZE=5
DATABASE_NAME=#{db_name}
TEST_DATABASE_NAME=#{db_name}_test
SHELL
file ".env.example", env
file ".env", env
append_to_file ".gitignore", "/.env\n"

remove_file "config/secrets.yml"
file "config/secrets.yml", <<-YAML
# http://guides.rubyonrails.org/4_1_release_notes.html#config-secrets-yml
development: &default
  secret_key_base: <%= ENV["SECRET_KEY_BASE"] %>
test:
  <<: *default
YAML

remove_file "config/database.yml"
file "config/database.yml", <<-YAML
default: &default
  adapter: postgresql
  encoding: utf8
  host: <%= ENV["DATABASE_HOST"] %>
  pool: <%= ENV["DATABASE_POOL_SIZE"] %>
  database: <%= ENV["DATABASE_NAME"] %>

development:
  <<: *default

test:
  <<: *default
  database: <%= ENV["TEST_DATABASE_NAME"] %>

production:
  <<: *default
  username: <%= ENV["DATABASE_USERNAME"] %>
  password: <%= ENV["DATABASE_PASSWORD"] %>
YAML

# Set up DB
rake("db:drop db:create")

# Foreman (Procfile)
file "Procfile", <<-YAML
web: spring rails server
YAML

# Setup devise
if use_auth
  generate "devise:install"
  generate "devise User"

  run %Q{sed -e "s/.*config.secret_key.*/  config.secret_key = Rails.application.secrets.secret_key_base || '#{SecureRandom.hex(32)}'/" config/initializers/devise.rb > config/initializers/devise_new.rb}
  run 'mv config/initializers/devise_new.rb config/initializers/devise.rb'
end
rake("db:migrate")

# Setup docker
if use_docker
  file "Dockerfile", <<-DOCKERFILE
FROM ruby:2.1.5
MAINTAINER AddJam

ENV RAILS_ENV production

# Ruby
RUN gem install bundler --no-ri --no-rdoc

# Add gemfile before others for better caching
WORKDIR /var/www
ADD Gemfile Gemfile
ADD Gemfile.lock Gemfile.lock
RUN bundle install

# Code
ADD . /var/www
RUN bundle exec rake assets:clean assets:precompile

# Env
EXPOSE 3000
CMD bundle exec puma -p 3000 -e production
  DOCKERFILE

  file "fig.yml", <<-FIG
web:
  image: #{docker_tag}:latest
  links:
    - "db:db"
  ports:
    - "3000:3000"
  volumes:
    - "./log:/var/www/log"
  environment:
    - "SECRET_KEY_BASE=#{SecureRandom.hex(32)}"
    - "DEVISE_KEY=#{SecureRandom.hex(32)}"
    - "VIRTUAL_HOST=#{domain}"
pgdata:
  image: busybox
  volumes:
    - /var/lib/postgresql/data
db:
  image: postgres
  volumes_from:
    - pgdata
  environment:
    - "LC_ALL=C.UTF-8"
nginx:
  image: jwilder/nginx-proxy:latest
  ports:
    - "80:80"
  volumes:
    - /var/run:/tmp
  FIG

  run "docker build -t #{docker_tag}:latest ."
end

# Finish
after_bundle do
  git :init
  git add: "."
  git commit: %Q{ -m 'Initial commit' }

  puts <<-WHATNOW

==============================================================================

  You have a Jam Jar, now Add Jam!

  # What next?

  - Copy .env.example to .env and change the environment variables
  - Setup skylight: $ bundle exec skylight setup skylight-key-here
    - https://www.skylight.io/app/setup
  - Run without docker: $ foreman start
  #{"- Run with docker (you'll need fig installed): $ fig up" if use_docker}
  #{"- Set MAINTAINER in the Dockerfile" if use_docker}
  #{"- Look at devise setup instructions (scroll up to gem install)" if use_auth}

  Built by Add Jam, inspired by suspenders & spawnpoint
  https://github.com/addjam/jamjar

==============================================================================

  WHATNOW
end