# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "openai_rate_limiter"

require "minitest/autorun"
require "minitest/pride"

require "async"
