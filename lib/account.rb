class Account
  TYPES = %i(asset expense liability revenue equity)

  attr :name, :open_date, :opening_balance, :parent_id, :tags, :type
  private :opening_balance

  def initialize params = {}
    @name            = params.fetch :name
    @offset          = 0
    @open_date       = params.fetch :open_date, Projector::ABSOLUTE_START
    @opening_balance = params.fetch :opening_balance, 0
    @parent_id       = params.fetch :parent_id, nil
    @tags            = Array(params[:tags])
    @type            = params.fetch :type
  end

  def apply_transaction_entry! entry
    @offset =
      if %i(asset expense).include? type
        entry.credit? ? (@offset - entry.amount) : (@offset + entry.amount)
      else
        entry.credit? ? (@offset + entry.amount) : (@offset - entry.amount)
      end
  end

  def asset_or_expense?
    %i(asset expense).include? type
  end

  def balance
    opening_balance + @offset
  end

  def inspect
    "#<#{self.class} name=#{name.inspect}, type=#{type.inspect}, balance=#{balance.round(2).to_f.inspect}>"
  end

  def tag? tag
    tags.include? tag
  end

  def self.default_account_name account_id
    account_id.to_s.capitalize.gsub(/_[a-z]/) do |dash_letter|
      dash_letter[1].upcase
    end
  end
end
