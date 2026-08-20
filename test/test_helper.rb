ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # 署名のテスト用ストローク。
    #
    # time を必ず含めること。各点の time から筆速・筆順が復元でき、
    # 模倣筆跡の検出力はここに依存している。座標だけに間引いた値を
    # テストの既定にすると、間引く実装が入っても誰も気づかない。
    SIGNATURE_STROKES = [
      { "points" => [
        { "x" => 10.0, "y" => 20.0, "time" => 1_700_000_000_000, "pressure" => 0.5 },
        { "x" => 42.0, "y" => 26.0, "time" => 1_700_000_000_120, "pressure" => 0.6 }
      ] }
    ].freeze

    # 1x1 の PNG（署名画像の添付を通すための最小データ）
    SIGNATURE_PNG_DATA_URL = "data:image/png;base64," \
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

    # Add more helper methods to be used by all tests here...
  end
end
