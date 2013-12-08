module MudratProjector
  class Account
    TYPES = %i(asset expense liability revenue equity)

    attr :open_date, :parent_id, :tags, :type

    def initialize params = {}
      @entries         = []
      @open_date       = params[:open_date] || ABSOLUTE_START
      @offset          = 0
      @opening_balance = params[:opening_balance] || 0
      @parent_id       = params[:parent_id] || nil
      @tags            = params[:tags] || []
      @type            = params.fetch :type
    end

    def add_entry entry
      @entries.push entry
      @offset += entry.delta
    end

    def balance
      @opening_balance + @offset
    end

    def close!
      freeze
      return self if closed?
      self.class.new serialize
    end

    def closed?
      @entries.empty?
    end

    def create_child params = {}
      new_params = serialize
      new_params.merge!(
        opening_balance: params[:opening_balance],
        parent_id: params.fetch(:parent_id),
        tags: (tags | Array(params[:tags])),
      )
      self.class.new new_params
    end

    def parent?
      parent_id.nil? ? false : true
    end

    def tag? tag_name
      tags.include? tag_name
    end

    def serialize
      hash = { opening_balance: balance }
      %i(open_date parent_id tags type).each do |attr|
        value = public_send attr
        unless default_value? attr, value
          hash[attr] = value unless Array(value).empty?
        end
      end
      hash
    end

    private

    def default_value? attr, value
      if attr == :open_date
        value == ABSOLUTE_START
      else
        false
      end
    end
  end
end
