# OpenAIRateLimiter

`OpenAIRateLimiter` is a Ruby gem that provides a robust, thread-safe rate limiter for OpenAI API requests. It helps you respect OpenAI's rate limits for both requests and tokens, and supports concurrent usage across threads and async tasks. The limiter automatically paces requests, handles rate limit headers, and ensures you don't exceed the specified concurrency.

## Features

- Global semaphore to limit concurrent API calls (default: 8)
- Automatic pacing between requests based on rate limit headers
- Handles both request and token limits
- Supports async and concurrent usage (via the `async` gem)
- Gracefully handles `Retry-After` headers

## Installation

Install the gem and add it to your application's Gemfile by executing:

    $ bundle add openai_rate_limiter

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install openai_rate_limiter

## Usage

Wrap your OpenAI API calls with the limiter to ensure you respect rate limits:

```ruby
require "openai_rate_limiter"

limiter = OpenAIRateLimiter.new

response = limiter.call(estimated_tokens: 1000) do
  # Make your OpenAI API request here
  # For example:
  client.completions(parameters)
end
```

The limiter will automatically pace requests and update the request management state from response headers.

### With Async (for concurrency)

```ruby
require "async"
require "openai_rate_limiter"

limiter = OpenAIRateLimiter.new

Async do
  10.times.map do
    Async do
      limiter.call(estimated_tokens: 500) do
        # Make your OpenAI API request here
      end
    end
  end.each(&:wait)
end
```

## How it works

- The limiter uses a global semaphore to cap concurrent requests (default: 8).
- It paces requests based on the last request time and the interval derived from rate limit headers.
- It tracks and respects both request and token limits, waiting for resets as needed.
- It updates its internal state from OpenAI response headers after each call.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/gjtorikian/openai_rate_limiter. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/gjtorikian/openai_rate_limiter/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the OpenAIRateLimiter project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/gjtorikian/openai_rate_limiter/blob/main/CODE_OF_CONDUCT.md).
