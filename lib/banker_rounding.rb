module BankerRounding
  def with_banker_rounding
    old_rounding_mode = BigDecimal.mode BigDecimal::ROUND_MODE
    BigDecimal.mode BigDecimal::ROUND_MODE, BigDecimal::ROUND_HALF_EVEN
    yield
  ensure
    BigDecimal.mode BigDecimal::ROUND_MODE, old_rounding_mode
  end
end
