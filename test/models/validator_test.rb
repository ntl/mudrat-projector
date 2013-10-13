require 'test_helper'

class ValidatorTest < Minitest::Unit::TestCase
  def setup
    @projector = Projector.new from: jan_1_2000
    @projector.add_account :checking, type: :asset
    @projector.add_account :job,      type: :revenue
  end

  def test_cannot_add_transaction_without_entriess
    assert_raises Projector::InvalidTransaction do
      @projector.add_transaction(
        date: jan_1_2000
      )
    end
    assert_raises Projector::InvalidTransaction do
      @projector.add_transaction(
        date: jan_1_2000,
        credits: [],
        debits:  [],
      )
    end
  end

  def test_past_transaction
    assert_raises Projector::InvalidTransaction do
      @projector.add_transaction(
        date: dec_31_1999,
        credit: { amount: 1000, account_id: :job      },
        debit:  { amount: 1000, account_id: :checking },
      )
    end
  end

  def test_cannot_add_single_transaction_which_does_not_balance
    assert_raises Projector::BalanceError do
      @projector.add_transaction(
        date: jan_1_2000,
        credit: { amount: 1000, account_id: :job      },
        debit:  { amount: 999,  account_id: :checking },
      )
    end
  end

end
