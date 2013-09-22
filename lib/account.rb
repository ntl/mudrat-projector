class Account
  TYPES = %i(asset expense liability revenue equity)

  attr :id, :name, :open_date, :opening_balance, :parent_id, :type

  def initialize id, params = {}
    @id              = id
    @name            = params.fetch :name, default_account_name
    @open_date       = params.fetch :open_date, Projector::ABSOLUTE_START
    @opening_balance = params.fetch :opening_balance, 0
    @parent_id       = params.fetch :parent_id, nil
    @type            = params.fetch :type
  end

  def validate! projector
    existing_account = projector.accounts[id]
    if existing_account
      raise Projector::AccountExists, "Account `#{id}' exists; name is "\
        "`#{existing_account.name}'"
    end
    unless TYPES.include? type
      raise Projector::InvalidAccount, "Account `#{name}', does not have a "\
        "type in #{TYPES.join(', ')}"
    end
    if opening_balance > 0 && open_date > projector.from
      raise Projector::BalanceError, "Projection starts on #{projector.from}, "\
        "and account `#{name}' starts on #{open_date} with a nonzero opening "\
        "balance of #{opening_balance}"
    end
  end

  def split into: []
    into.map do |child_id|
      self.class.new(
        child_id,
        open_date: open_date,
        parent_id: id,
        type:      type,
      )
    end
  end

  private

  def default_account_name
    id.to_s.capitalize.gsub(/_[a-z]/) do |dash_letter|
      dash_letter[1].upcase
    end
  end
end
