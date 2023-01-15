# frozen_string_literal: true

require 'forwardable'

module JWT
  module JWK
    class EC < KeyBase # rubocop:disable Metrics/ClassLength
      extend Forwardable
      def_delegators :keypair, :public_key

      KTY    = 'EC'
      KTYS   = [KTY, OpenSSL::PKey::EC, JWT::JWK::EC].freeze
      BINARY = 2
      EC_PUBLIC_KEY_ELEMENTS = %i[kty crv x y].freeze
      EC_PRIVATE_KEY_ELEMENTS = %i[d].freeze
      EC_KEY_ELEMENTS = (EC_PRIVATE_KEY_ELEMENTS + EC_PUBLIC_KEY_ELEMENTS).freeze

      def initialize(key, params = nil, options = {})
        params ||= {}

        # For backwards compatibility when kid was a String
        params = { kid: params } if params.is_a?(String)

        key_params = extract_key_params(key)

        params = params.transform_keys(&:to_sym)
        check_jwk(key_params, params)

        super(options, key_params.merge(params))
      end

      def keypair
        @keypair ||= create_ec_key(self[:crv], self[:x], self[:y], self[:d])
      end

      def private?
        keypair.private_key?
      end

      def members
        EC_PUBLIC_KEY_ELEMENTS.each_with_object({}) { |i, h| h[i] = self[i] }
      end

      def export(options = {})
        exported = parameters.clone
        exported.reject! { |k, _| EC_PRIVATE_KEY_ELEMENTS.include? k } unless private? && options[:include_private] == true
        exported
      end

      def key_digest
        _crv, x_octets, y_octets = keypair_components(keypair)
        sequence = OpenSSL::ASN1::Sequence([OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(x_octets, BINARY)),
                                            OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(y_octets, BINARY))])
        OpenSSL::Digest::SHA256.hexdigest(sequence.to_der)
      end

      def []=(key, value)
        if EC_KEY_ELEMENTS.include?(key.to_sym)
          raise ArgumentError, 'cannot overwrite cryptographic key attributes'
        end

        super(key, value)
      end

      private

      def extract_key_params(key)
        case key
        when JWT::JWK::EC
          key.export(include_private: true)
        when OpenSSL::PKey::EC # Accept OpenSSL key as input
          @keypair = key # Preserve the object to avoid recreation
          parse_ec_key(key)
        when Hash
          key.transform_keys(&:to_sym)
        else
          raise ArgumentError, 'key must be of type OpenSSL::PKey::EC or Hash with key parameters'
        end
      end

      def check_jwk(keypair, params)
        raise ArgumentError, 'cannot overwrite cryptographic key attributes' unless (EC_KEY_ELEMENTS & params.keys).empty?
        raise JWT::JWKError, "Incorrect 'kty' value: #{keypair[:kty]}, expected #{KTY}" unless keypair[:kty] == KTY
        raise JWT::JWKError, 'Key format is invalid for EC' unless keypair[:crv] && keypair[:x] && keypair[:y]
      end

      def keypair_components(ec_keypair)
        encoded_point = ec_keypair.public_key.to_bn.to_s(BINARY)
        case ec_keypair.group.curve_name
        when 'prime256v1'
          crv = 'P-256'
          x_octets, y_octets = encoded_point.unpack('xa32a32')
        when 'secp256k1'
          crv = 'P-256K'
          x_octets, y_octets = encoded_point.unpack('xa32a32')
        when 'secp384r1'
          crv = 'P-384'
          x_octets, y_octets = encoded_point.unpack('xa48a48')
        when 'secp521r1'
          crv = 'P-521'
          x_octets, y_octets = encoded_point.unpack('xa66a66')
        else
          raise JWT::JWKError, "Unsupported curve '#{ec_keypair.group.curve_name}'"
        end
        [crv, x_octets, y_octets]
      end

      def encode_octets(octets)
        return unless octets

        ::JWT::Base64.url_encode(octets)
      end

      def encode_open_ssl_bn(key_part)
        ::JWT::Base64.url_encode(key_part.to_s(BINARY))
      end

      def parse_ec_key(key)
        crv, x_octets, y_octets = keypair_components(key)
        octets = key.private_key&.to_bn&.to_s(BINARY)
        {
          kty: KTY,
          crv: crv,
          x: encode_octets(x_octets),
          y: encode_octets(y_octets),
          d: encode_octets(octets)
        }.compact
      end

      if ::JWT.openssl_3?
        def create_ec_key(jwk_crv, jwk_x, jwk_y, jwk_d) # rubocop:disable Metrics/MethodLength
          curve = EC.to_openssl_curve(jwk_crv)

          x_octets = decode_octets(jwk_x)
          y_octets = decode_octets(jwk_y)

          point = OpenSSL::PKey::EC::Point.new(
            OpenSSL::PKey::EC::Group.new(curve),
            OpenSSL::BN.new([0x04, x_octets, y_octets].pack('Ca*a*'), 2)
          )

          sequence = if jwk_d
            # https://datatracker.ietf.org/doc/html/rfc5915.html
            # ECPrivateKey ::= SEQUENCE {
            #   version        INTEGER { ecPrivkeyVer1(1) } (ecPrivkeyVer1),
            #   privateKey     OCTET STRING,
            #   parameters [0] ECParameters {{ NamedCurve }} OPTIONAL,
            #   publicKey  [1] BIT STRING OPTIONAL
            # }

            OpenSSL::ASN1::Sequence([
                                      OpenSSL::ASN1::Integer(1),
                                      OpenSSL::ASN1::OctetString(OpenSSL::BN.new(decode_octets(jwk_d), 2).to_s(2)),
                                      OpenSSL::ASN1::ObjectId(curve, 0, :EXPLICIT),
                                      OpenSSL::ASN1::BitString(point.to_octet_string(:uncompressed), 1, :EXPLICIT)
                                    ])
          else
            OpenSSL::ASN1::Sequence([
                                      OpenSSL::ASN1::Sequence([OpenSSL::ASN1::ObjectId('id-ecPublicKey'), OpenSSL::ASN1::ObjectId(curve)]),
                                      OpenSSL::ASN1::BitString(point.to_octet_string(:uncompressed))
                                    ])
          end

          OpenSSL::PKey::EC.new(sequence.to_der)
        end
      else
        def create_ec_key(jwk_crv, jwk_x, jwk_y, jwk_d)
          curve = EC.to_openssl_curve(jwk_crv)

          x_octets = decode_octets(jwk_x)
          y_octets = decode_octets(jwk_y)

          key = OpenSSL::PKey::EC.new(curve)

          # The details of the `Point` instantiation are covered in:
          # - https://docs.ruby-lang.org/en/2.4.0/OpenSSL/PKey/EC.html
          # - https://www.openssl.org/docs/manmaster/man3/EC_POINT_new.html
          # - https://tools.ietf.org/html/rfc5480#section-2.2
          # - https://www.secg.org/SEC1-Ver-1.0.pdf
          # Section 2.3.3 of the last of these references specifies that the
          # encoding of an uncompressed point consists of the byte `0x04` followed
          # by the x value then the y value.
          point = OpenSSL::PKey::EC::Point.new(
            OpenSSL::PKey::EC::Group.new(curve),
            OpenSSL::BN.new([0x04, x_octets, y_octets].pack('Ca*a*'), 2)
          )

          key.public_key = point
          key.private_key = OpenSSL::BN.new(decode_octets(jwk_d), 2) if jwk_d

          key
        end
      end

      def decode_octets(jwk_data)
        ::JWT::Base64.url_decode(jwk_data)
      end

      def decode_open_ssl_bn(jwk_data)
        OpenSSL::BN.new(::JWT::Base64.url_decode(jwk_data), BINARY)
      end

      class << self
        def import(jwk_data)
          new(jwk_data)
        end

        def to_openssl_curve(crv)
          # The JWK specs and OpenSSL use different names for the same curves.
          # See https://tools.ietf.org/html/rfc5480#section-2.1.1.1 for some
          # pointers on different names for common curves.
          case crv
          when 'P-256' then 'prime256v1'
          when 'P-384' then 'secp384r1'
          when 'P-521' then 'secp521r1'
          when 'P-256K' then 'secp256k1'
          else raise JWT::JWKError, 'Invalid curve provided'
          end
        end
      end
    end
  end
end
