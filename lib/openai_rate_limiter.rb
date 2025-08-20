# frozen_string_literal: true

require_relative "openai_rate_limiter/version"

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "openai" => "OpenAI",
)

loader.setup

require "async"
require "async/semaphore"

class OpenAIRateLimiter
  # Global semaphore shared across all RateLimiter instances
  # This ensures we never exceed max concurrent API calls globally
  GLOBAL_SEMAPHORE = Async::Semaphore.new(ENV.fetch("OPENAI_MAX_CONCURRENT_REQUESTS", 8).to_i)

  def initialize
    @interval = 0.5 # initial pacing (seconds per request)
    @last_request_time = 0

    @tokens_remaining = nil
    @tokens_reset_time = nil
    @requests_remaining = nil
    @requests_reset_time = nil
  end

  def call(estimated_tokens: 0)
    GLOBAL_SEMAPHORE.acquire do
      # Wait until next request slot
      now = Time.now.to_f
      wait_time = @last_request_time + @interval - now
      Kernel.sleep(wait_time) if wait_time > 0

      # If token limit known, wait if necessary
      if @tokens_remaining && @tokens_remaining < estimated_tokens
        sleep_time = @tokens_reset_time - now
        Kernel.sleep(sleep_time) if sleep_time > 0
      end

      # If request limit known, wait if necessary
      if @requests_remaining && @requests_remaining <= 0
        sleep_time = @requests_reset_time - now
        Kernel.sleep(sleep_time) if sleep_time > 0
      end

      @last_request_time = Time.now.to_f

      response = yield

      update_from_headers(response) if response.respond_to?(:[])

      response
    end
  end

  private

  def update_from_headers(headers)
    # RPM
    if headers["x-ratelimit-limit-requests"]
      rpm = headers["x-ratelimit-limit-requests"].to_i
      @interval = 60.0 / rpm if rpm > 0
    end

    # Tokens
    if headers["x-ratelimit-remaining-tokens"] && headers["x-ratelimit-reset-tokens"]
      @tokens_remaining = headers["x-ratelimit-remaining-tokens"].to_i
      reset_epoch = headers["x-ratelimit-reset-tokens"].to_i
      @tokens_reset_time = Time.at(reset_epoch).to_f
    end

    # Total Requests
    if headers["x-ratelimit-remaining-requests"] && headers["x-ratelimit-reset-requests"]
      @requests_remaining = headers["x-ratelimit-remaining-requests"].to_i
      reset_epoch = headers["x-ratelimit-reset-requests"].to_i
      @requests_reset_time = Time.at(reset_epoch).to_f
    end

    # Retry-After
    return unless headers["retry-after"]

    delay = headers["retry-after"].to_f
    @last_request_time = Time.now.to_f + delay
  end
end
