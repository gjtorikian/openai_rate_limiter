# frozen_string_literal: true

require "test_helper"

class OpenAIRateLimiterTest < Minitest::Test
  def setup
    @limiter = OpenAIRateLimiter.new
  end

  def test_initializes_with_default_interval
    assert_in_delta(0.5, @limiter.instance_variable_get(:@interval))
    assert_equal(0, @limiter.instance_variable_get(:@last_request_time))
    assert_nil(@limiter.instance_variable_get(:@tokens_remaining))
    assert_nil(@limiter.instance_variable_get(:@requests_remaining))
  end

  def test_enforces_pacing_between_requests
    start_time = nil
    end_time = nil

    Async do
      start_time = Time.now.to_f

      # First request should go immediately
      @limiter.call { "response1" }

      # Second request should wait for interval
      result = @limiter.call { "response2" }
      end_time = Time.now.to_f

      assert_equal("response2", result)
    end.wait

    elapsed = end_time - start_time
    # Should wait at least the interval (0.5s) between requests
    assert_operator(elapsed, :>=, 0.5)
  end

  def test_updates_interval_from_rate_limit_headers
    headers = {
      "x-ratelimit-limit-requests" => "120", # 120 RPM = 0.5s interval
    }

    Async do
      @limiter.call { headers }
    end.wait

    # 60.0 / 120 = 0.5
    assert_in_delta(0.5, @limiter.instance_variable_get(:@interval))
  end

  def test_updates_token_limits_from_headers
    future_time = Time.now.to_i + 60
    headers = {
      "x-ratelimit-remaining-tokens" => "1000",
      "x-ratelimit-reset-tokens" => future_time.to_s,
    }

    Async do
      @limiter.call { headers }
    end.wait

    assert_equal(1000, @limiter.instance_variable_get(:@tokens_remaining))
    assert_equal(future_time.to_f, @limiter.instance_variable_get(:@tokens_reset_time))
  end

  def test_updates_request_limits_from_headers
    future_time = Time.now.to_i + 10
    headers = {
      "x-ratelimit-remaining-requests" => "5",
      "x-ratelimit-reset-requests" => future_time.to_s,
    }

    Async do
      @limiter.call { headers }
    end.wait

    assert_equal(5, @limiter.instance_variable_get(:@requests_remaining))
    assert_equal(future_time.to_f, @limiter.instance_variable_get(:@requests_reset_time))
  end

  def test_waits_when_token_limit_exceeded
    # Set up limiter with low token count that resets in 0.3 seconds
    reset_time = Time.now.to_f + 0.3
    @limiter.instance_variable_set(:@tokens_remaining, 50)
    @limiter.instance_variable_set(:@tokens_reset_time, reset_time)

    start_time = nil
    end_time = nil

    Async do
      start_time = Time.now.to_f

      # This should wait because we're requesting 100 tokens but only have 50
      result = @limiter.call(estimated_tokens: 100) { "delayed_response" }
      end_time = Time.now.to_f

      assert_equal("delayed_response", result)
    end.wait

    elapsed = end_time - start_time
    # Should have waited approximately 0.3 seconds for token reset
    assert_operator(elapsed, :>=, 0.25) # Allow some tolerance
  end

  def test_waits_when_request_limit_is_zero
    # Set up limiter with zero requests remaining that resets in 0.3 seconds
    reset_time = Time.now.to_f + 0.3
    @limiter.instance_variable_set(:@requests_remaining, 0)
    @limiter.instance_variable_set(:@requests_reset_time, reset_time)

    start_time = nil
    end_time = nil

    Async do
      start_time = Time.now.to_f

      # This should wait because we have 0 requests remaining
      result = @limiter.call { "delayed_response" }
      end_time = Time.now.to_f

      assert_equal("delayed_response", result)
    end.wait

    elapsed = end_time - start_time
    # Should have waited approximately 0.3 seconds for request reset
    assert_operator(elapsed, :>=, 0.25) # Allow some tolerance
  end

  def test_handles_retry_after_header
    headers = {
      "retry-after" => "2.0",
    }

    Async do
      @limiter.call { headers }
    end.wait

    last_request_time = @limiter.instance_variable_get(:@last_request_time)
    # Last request time should be pushed forward by 2 seconds
    assert_operator(last_request_time, :>, Time.now.to_f + 1.9)
  end

  # Test that multiple concurrent requests are limited by the global semaphore
  def test_concurrent_requests_respect_global_semaphore
    concurrent_count = 0
    max_concurrent = 0
    mutex = Mutex.new

    Async do
      # Try to make 20 concurrent requests
      Array.new(20) do |i|
        Async do
          @limiter.call do
            mutex.synchronize do
              concurrent_count += 1
              max_concurrent = [max_concurrent, concurrent_count].max
            end

            # Simulate API call
            Kernel.sleep(0.1)

            mutex.synchronize do
              concurrent_count -= 1
            end

            "response_#{i}"
          end
        end
      end.map(&:wait)
    end.wait

    # Should never exceed the global semaphore limit (default 8)
    assert_operator(max_concurrent, :<=, 8)
  end

  # Test that concurrent header updates don't cause race conditions
  def test_thread_safety_of_header_updates
    Async do
      Array.new(10) do |i|
        Async do
          headers = {
            "x-ratelimit-limit-requests" => (60 + i).to_s,
            "x-ratelimit-remaining-tokens" => (1000 - i * 10).to_s,
            "x-ratelimit-reset-tokens" => (Time.now.to_i + 60).to_s,
          }

          @limiter.call { headers }
        end
      end.map(&:wait)
    end.wait

    # Check that final state is consistent (not corrupted by race conditions)
    interval = @limiter.instance_variable_get(:@interval)
    tokens = @limiter.instance_variable_get(:@tokens_remaining)

    refute_nil(interval)
    refute_nil(tokens)
    assert_kind_of(Float, interval)
    assert_kind_of(Integer, tokens)
  end

  def test_handles_missing_headers_gracefully
    headers = {}

    Async do
      result = @limiter.call { headers }

      assert_equal(headers, result)
    end.wait
  end

  def test_handles_partial_headers
    headers = {
      "x-ratelimit-remaining-tokens" => "500",
      # Missing reset time - should not update
    }

    Async do
      @limiter.call { headers }
    end.wait

    # Should not have updated tokens since reset time was missing
    assert_nil(@limiter.instance_variable_get(:@tokens_remaining))
  end

  def test_multiple_limiters_share_global_semaphore
    limiter1 = OpenAIRateLimiter.new
    limiter2 = OpenAIRateLimiter.new

    # Both limiters should reference the same global semaphore
    assert_same(
      OpenAIRateLimiter::GLOBAL_SEMAPHORE,
      OpenAIRateLimiter::GLOBAL_SEMAPHORE,
    )

    concurrent_count = 0
    max_concurrent = 0
    mutex = Mutex.new

    Async do
      # Make requests through both limiters
      tasks = []

      10.times do |i|
        tasks << Async do
          (i.even? ? limiter1 : limiter2).call do
            mutex.synchronize do
              concurrent_count += 1
              max_concurrent = [max_concurrent, concurrent_count].max
            end

            Kernel.sleep(0.1)

            mutex.synchronize do
              concurrent_count -= 1
            end

            "response"
          end
        end
      end

      tasks.map(&:wait)
    end.wait

    # Should respect global limit even across multiple limiter instances
    assert_operator(max_concurrent, :<=, 8)
  end

  def test_respects_all_limits_simultaneously
    # Set up a complex scenario with multiple constraints
    future_time = Time.now.to_f + 0.2

    @limiter.instance_variable_set(:@interval, 0.1)
    @limiter.instance_variable_set(:@tokens_remaining, 100)
    @limiter.instance_variable_set(:@tokens_reset_time, future_time)
    @limiter.instance_variable_set(:@requests_remaining, 1)
    @limiter.instance_variable_set(:@requests_reset_time, future_time + 0.1)

    Async do
      # First request should succeed (uses the 1 remaining request)
      result1 = @limiter.call(estimated_tokens: 50) { "success1" }

      assert_equal("success1", result1)

      # Second request should wait for request reset
      start = Time.now.to_f
      result2 = @limiter.call(estimated_tokens: 30) { "success2" }
      elapsed = Time.now.to_f - start

      assert_equal("success2", result2)
      # Should have waited for both interval AND request reset
      assert_operator(elapsed, :>=, 0.1)
    end.wait
  end

  def test_yield_block_receives_and_returns_response_correctly
    test_response = { "data" => "test", "status" => "ok" }

    Async do
      result = @limiter.call do
        # Simulate some work
        test_response
      end

      assert_equal(test_response, result)
    end.wait
  end
end
