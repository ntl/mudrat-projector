require 'test_helper'

class ProjectionTest < Minitest::Unit::TestCase
  def setup
    @projector = Projector.new from: jan_1_2000
  end

  def method_missing sym, *args, &block
    return super if block_given? || args.size > 0
    begin
      Date.parse sym.to_s
    rescue ArgumentError => ae
      super
    end
  end

  private

  def epoch
    jan_1_1970
  end

  def projection
    @projector.project to: dec_31_2000
  end
end

class ProjectorAccountsTest < ProjectionTest
  def test_add_account_defaults_name_to_id_when_hash_is_supplied
    @projector.add_account :checking, type: :asset
    assert_equal 'Checking', @projector.accounts[:checking].name
  end

  def test_add_account_refuses_to_overwrite_account
    @projector.add_account :checking, type: :asset
    assert_raises Projector::AccountExists do
      @projector.add_account :checking, type: :asset
    end
  end

  def test_add_account_refuses_to_add_account_without_valid_type
    assert_raises Projector::InvalidAccount do
      @projector.add_account :checking, type: nil
    end
    assert_raises Projector::InvalidAccount do
      @projector.add_account :checking, type: :foozle
    end
  end

  def test_add_accounts_defaults_open_date_to_start_of_projection
    @projector.add_account :checking, type: :asset
    assert_equal jan_1_2000, @projector.accounts[:checking].open_date
  end

  def test_adding_a_sub_account
    parent = @projector.add_account(
      :checking,
      open_date: jan_8_2000,
      type:      :asset,
    )

    child, _ = @projector.split_account :checking, into: %i(checking_sub_1 checking_sub_2)

    assert_equal :checking,  child.parent_id
    assert_equal jan_8_2000, child.open_date
    assert_equal :asset,     child.type
  end

  def test_add_accounts_passes_account_hashes_to_add_account
    assert_equal 0, @projector.accounts.size
    @projector.accounts = { checking: { type: :asset } }
    assert_equal 1, @projector.accounts.size
  end
end

class ProjectorSingleTransactionTest < ProjectionTest
  def setup
    super
    @projector.add_account :checking, type: :asset
    @projector.add_account :nustartup_inc, type: :revenue
  end

  def test_single_transaction_without_split
    @projector.add_transaction(
      date: jan_1_2000,
      credit: [1000, :nustartup_inc],
      debit:  [1000, :checking],
    )

    assert_equal 1000, projection.closing_equity
    assert_equal [0, 1000], projection.accounts[:checking].delta
    assert_equal [0, 1000], projection.accounts[:nustartup_inc].delta
  end

  def test_single_transaction_to_sub_account_without_split
    @projector.split_account :checking, into: %i(checking_sub_1 checking_sub_2)

    @projector.add_transaction(
      date: jan_1_2000,
      credit: [1000, :nustartup_inc],
      debit:  [1000, :checking_sub_1],
    )

    assert_equal [0, 1000], projection.accounts.fetch(:checking).delta
    assert_equal [0, 1000], projection.accounts.fetch(:checking_sub_1).delta
    assert_equal [0, 0],    projection.accounts.fetch(:checking_sub_2).delta
  end

  def test_single_transaction_with_split
    @projector.add_account :savings, type: :asset
    @projector.add_transaction(
      date: jan_1_2000,
      credit: [1000, :nustartup_inc],
      debits: [ [500, :checking], [500, :savings]],
    )

    assert_equal 1000, projection.closing_equity
  end

  def test_recurring_transaction_surrounding_the_projection_range
    @projector.add_transaction(
      credit: [4000, :nustartup_inc],
      debit:  [4000, :checking],
      recurring_schedule: [1, :month],
    )
    assert_equal 48000, projection.closing_equity
  end

  def test_recurring_transaction_within_the_projection_range
    @projector.add_transaction(
      credit: [4000, :nustartup_inc],
      debit:  [4000, :checking],
      date: feb_1_2000,
      recurring_schedule: [1, :month, may_31_2000],
    )
    assert_equal 16000, projection.closing_equity
  end

  def test_single_transaction_which_does_not_balance
    assert_raises Projector::BalanceError do
      @projector.add_transaction(
        date: jan_1_2000,
        credit: [1000, :nustartup_inc],
        debit:  [999, :checking],
      )
    end

    @projector.add_account :savings, type: :asset
    @projector.add_transaction(
      date: jan_1_2000,
      credit: [1000, :nustartup_inc],
      debits: [
        [999, :checking],
        [1, :savings],
      ],
    )
  end

  def test_add_transactions_passes_transactions_hashes_to_add_transaction
    assert_equal 0, @projector.transactions.size
    @projector.transactions = [{
      date: jan_1_2000,
      credit: [1000, :nustartup_inc],
      debit:  [1000, :checking],
    }]
    assert_equal 1, @projector.transactions.size
  end
end
