begin
  require 'mail/check_delivery_params'
  require 'simpleidn'
rescue LoadError
end

module Mail
  class Sendgrid
    include ::Mail::CheckDeliveryParams rescue nil

    attr_accessor :settings, :client, :xsmtp

    def initialize(options={})
      self.settings = {
        api_user: nil,
        api_key: nil
      }.merge!(options)

      @client = SendgridApi::Client.new(self.settings)
    end

    def deliver!(mail)
      check_delivery_params(mail)

      # Extract the recipients, allows array of strings, array of addresses or comma separated string
      to = mail[:to].value
      to = to.split(",").collect(&:strip) if to.is_a? String

      to = parse_email_address(to)
      if (mail[:bcc])
        bcc = mail[:bcc].value
        bcc = bcc.split(",").collect(&:strip) if bcc.is_a? String
        bcc = parse_email_address(bcc).map(&:address)
      end

      # Set the Return-Path header if we have a from email address
      from = parse_email_address(mail[:from].value).first
      mail.header["Return-Path"] = from.address if mail.header["Return-Path"].nil?

      # Put Reply-To on the headers as Sendgrid Web API only accepts an address
      mail.header["Reply-To"] = parse_email_address(mail[:reply_to].value).first if (mail[:reply_to])

      # Call .to_s to force into JSON as Mail < 2.5 doesn't
      xsmtp = parse_xsmtpapi_headers(mail)
      @mailer = SendgridApi::Mail.new(@client, xsmtp: xsmtp)

      # Pass everything through, .queue will remove nils
      result = @mailer.queue(
        to:       to.collect(&:address),
        toname:   to.collect(&:name),
        from:     from.address,
        fromname: from.display_name,
        bcc:      bcc,
        subject:  mail.subject,
        text:     mail.text_part.to_s.length > 0 && mail.text_part.body,
        html:     mail.html_part.to_s.length > 0 && mail.html_part.body,
        headers:  header_to_hash(mail).to_json
      )
      raise SendgridApi::Error::DeliveryError.new(result.message) if result.error?
      return result
    end

    # Simple check of required Mail params if superclass doesn't exist from 2.5.0
    # @param [Mail] mail
    #
    def check_delivery_params(mail)
      if defined?(super)
        super
      else
        blank = proc { |t| t.nil? || t.empty? }
        if [mail.from, mail.to].any?(&blank) || [mail.html_part, mail.text_part].all?(&blank)
          raise ArgumentError.new("Missing required mail part")
        end
      end
    end

    private

    # Convert Mail::Header fields to Hash and remove specific params
    # @param [Mail] mail
    # @return [Hash]
    #
    def header_to_hash(mail)
      reject_keys = %w(To From Bcc Subject X-SMTPAPI)
      if mail['Content-Type'] && mail['Content-Type'].value.start_with?('multipart/alternative')
        reject_keys.concat %w(Content-Type Mime-Version)
      end
      mail.header_fields.each_with_object(Hash.new) do |field, hash|
        next if reject_keys.include?(field.name)
        hash[field.name] = field.value
      end
    end

    # Extract the ::Mail header['X-SMTPAPI'] value and call SendgridApi::Mail methods to build JSON
    # @param [Mail]
    #
    def parse_xsmtpapi_headers(mail)
      mail.header['X-SMTPAPI'].value.to_s if mail.header['X-SMTPAPI']
    end

    # Parse the email address, and rescue any Parse errors
    # @param [String] email
    # @return [Array] Mail::Address
    #
    def parse_email_address(email)
      Array(email).collect { |email| Mail::Address.new(email) }
    rescue Mail::Field::ParseError => e
      punycode_email(email)
    end

    # convert email domain names containing unicode characters to punycode
    # @param [String] email
    # @return [Array] Mail::Address
    #
    def punycode_email(email)
      Array(email).collect do |email|
        email_part, display_name = email.split(/\<(.*?)\>/).reverse
        email = Mail::Address.new(SimpleIDN.to_ascii(email_part))
        email.tap{ |m| m.display_name = display_name.tr!('"','').strip!} if display_name
        email
      end
    end

  end
end
