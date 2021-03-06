# encoding: utf-8
require 'spec_helper'

module Mail
  describe "sendgrid" do
    subject(:mailer) { Sendgrid.new }

    describe ".initialize" do
      it "should initialize a new SendgridApi::Client" do
        expect(subject.client).to be_kind_of(SendgridApi::Client)
      end
    end

    describe ".deliver!" do
      let(:filter)   {
        {filters: {opentrack: {settings: {enable: 1}}}}.to_json
      }
      let(:mail)     {
        Mail.new(
          from:     Mail::Address.new('"Tester" <from@address.com>'), # Or just "Tester" <from@address.com>
          to:       "to@address.com",
          bcc:      "bcc@address.com",
          reply_to: Mail::Address.new('"Reply" <reply@address.com>'),
          subject:  "Rspec test",
          headers:  {"X-SMTPAPI" => filter}
          ) do
            text_part { body 'This is plain text' }
          end
      }
      let(:success) { SendgridApi::Result.new({message: "success"}) }

      context "valid email" do
        it "should return a successful response" do
          expect(subject.client).to receive(:post).with(
            "send",
            nil,
            hash_including(
              to:       ["to@address.com"],
              toname:   [nil],
              from:     "from@address.com",
              fromname: "Tester",
              bcc:      ["bcc@address.com"],
              subject:  "Rspec test",
              text:     kind_of(::Mail::Body),
              headers:  kind_of(String),
              "x-smtpapi".to_sym => filter
            )

          ).and_return(success)

          expect(subject.deliver!(mail)).to eq success
        end

        it "should build the headers" do
          expect(subject.client).to receive(:post).with(
            "send",
            nil,
            hash_including(
              headers: include(
                '"Return-Path":"from@address.com"',
                '"Reply-To":"Reply <reply@address.com>"',
                '"Content-Type":"multipart/mixed"'
              )
            )

          ).and_return(success)

          expect(subject.deliver!(mail)).to eq success
        end
      end

      context "multiple recipients" do
        let(:to_mail)  {
          Mail.new(
            from:    Mail::Address.new('"Tester" <from@address.com>'), # Or just "Tester" <from@address.com>
            to:      ["Tester <to@address.com>", "Another <and@address.com>"],
            subject: "Rspec test"
          ) do
            text_part { body 'This is plain text' }
          end
        }

        it "should return a successful response" do
          expect(subject.client).to receive(:post).with(
            "send",
            nil,
            hash_including(
              to:       ["to@address.com", "and@address.com"],
              toname:   ["Tester", "Another"],
              from:     "from@address.com",
              fromname: "Tester",
              subject:  "Rspec test"
            )
          ).and_return(success)

          expect(subject.deliver!(to_mail)).to eq success
        end

        it "should allow multiple recipients as a string" do
          expect(subject.client).to receive(:post).with(
            "send",
            nil,
            hash_including(
              to: ["to@address.com", "and@address.com"]
            )
          ).and_return(success)

          to_mail.to = "to@address.com, and@address.com"
          expect(subject.deliver!(to_mail)).to eq success
        end
      end

      context "for encoded display name" do
        let(:from) { Mail::Address.new("from@address.com").tap { |m| m.display_name = "José Publico" }.encoded }
        let(:mail) {
          Mail.new(
            from:     from,
            to:       to,
            subject:  "Rspec test"
          ) do
            text_part { body 'This is plain text' }
          end
        }

        context "addresses with non-ascii display name" do
          let(:to) { '"José Publico" <to@address.com>' }

          it "should send successfully" do
            expect(subject.client).to receive(:post).with(
              "send",
              nil,
              hash_including(
                to:       ["to@address.com"],
                toname:   ["José Publico"],
                from:     "from@address.com",
                fromname: "José Publico"
              )
            ).and_return(success)

            expect(subject.deliver!(mail)).to eq success
          end
        end

        context "addresses with Mail::Address addresses non-ascii display name" do
          let(:to) { Mail::Address.new("to@address.com").tap { |m| m.display_name = "José Publico" } }

          it "should send successfully" do
            expect(subject.client).to receive(:post).with(
              "send",
              nil,
              hash_including(
                to:       ["to@address.com"],
                toname:   ["José Publico"],
                from:     "from@address.com",
                fromname: "José Publico"
              )
            ).and_return(success)

            expect(subject.deliver!(mail)).to eq success
          end
        end

        context "addresses with Mail::Address with encoded non-ascii display name" do
          let(:to) { Mail::Address.new("to@address.com").tap { |m| m.display_name = "José Publico" }.encoded }

          it "should send successfully" do
            expect(subject.client).to receive(:post).with(
              "send",
              nil,
              hash_including(
                to:       ["to@address.com"],
                toname:   ["José Publico"],
                from:     "from@address.com",
                fromname: "José Publico"
              )
            ).and_return(success)

            expect(subject.deliver!(mail)).to eq success
          end
        end

        context "addresses with non-ascii domain name" do
          let(:to) { "jose@josépublic.com" }

          it "should punycode the domain and send successfully" do
            expect(subject.client).to receive(:post).with(
              "send",
              nil,
              hash_including(
                to:       ["xn--jose@jospublic-ikb.com"],
                from:     "from@address.com",
                fromname: "José Publico"
              )
            ).and_return(success)

            expect(subject.deliver!(mail)).to eq success
          end
        end

        context "addresses with non-ascii domain name and non-ascii local" do
          let(:to) { "jöse@josépublic.com" }

          it "should punycode the domain and send successfully" do
            expect(subject.client).to receive(:post).with(
              "send",
              nil,
              hash_including(
                to:       ["xn--jse@jospublic-hhb2q.com"],
                from:     "from@address.com",
                fromname: "José Publico"
              )
            ).and_return(success)

            expect(subject.deliver!(mail)).to eq success
          end
        end

        context "addresses with an ascii domain name and non-ascii local" do
          let(:to) { "jöse@josepublic.com" }

          it "should punycode the domain and local and send successfully" do
            expect(subject.client).to receive(:post).with(
              "send",
              nil,
              hash_including(
                to:       ["xn--jse@josepublic-vpb.com"],
                from:     "from@address.com",
                fromname: "José Publico"
              )
            ).and_return(success)

            expect(subject.deliver!(mail)).to eq success
          end
        end

        context "addresses with non-ascii domain name and non-ascii display name" do
          let(:to) { '"andrè "the" gïant" <to@àddress.com>' }

          it "should punycode the domain and send successfully" do
            expect(subject.client).to receive(:post).with(
              "send",
              nil,
              hash_including(
                to:       ["xn--to@ddress-s1a.com"],
                toname:   ["andrè \"the\" gïant"],
                from:     "from@address.com",
                fromname: "José Publico"
              )
            ).and_return(success)

            expect(subject.deliver!(mail)).to eq success
          end
        end
      end

      context "BCC recipients" do
        let(:bcc_mail)  {
          Mail.new(
            from:    '"Tester" <from@address.com>',
            to:      '"Tester <to@address.com>"',
            subject: "Rspec test",
            bcc:     ["Tester <bcc@address.com>", "Another <and@address.com>"],
          ) do
            text_part { body 'This is plain text' }
          end
        }

        it "should return a successful response with BCC addresses only" do
          expect(subject.client).to receive(:post).with(
            "send",
            nil,
            hash_including(
              bcc:      ["bcc@address.com", "and@address.com"],
              subject:  "Rspec test"
            )
          ).and_return(success)

          expect(subject.deliver!(bcc_mail)).to eq success
        end

        it "should allow multiple recipients as a string" do
          expect(subject.client).to receive(:post).with(
            "send",
            nil,
            hash_including(
              bcc:      ["bcc@address.com", "and@address.com"]
            )
          ).and_return(success)

          bcc_mail.to = "bcc@address.com, and@address.com"
          expect(subject.deliver!(bcc_mail)).to eq success
        end

        it "should allow an empty bcc" do
          expect(subject.client).to receive(:post).with(
            "send",
            nil,
            hash_excluding(:bcc)
          ).and_return(success)

          bcc_mail.bcc = nil
          expect(subject.deliver!(bcc_mail)).to eq success
        end
      end

      context "multiple from addresses" do
        let(:from_mail)  {
          Mail.new(
            from:    '"Tester" <from@address.com>, Another tester <from2@address.com>',
            to:      'Tester <to@address.com>',
            subject: "Rspec test"
          ) do
            text_part { body 'This is plain text' }
          end
        }

        it "should return a successful response" do
          expect(subject.client).to receive(:post).with(
            "send",
            nil,
            hash_including(
              from:     "from@address.com",
              fromname: "Tester",
              subject:  "Rspec test"
            )
          ).and_return(success)

          expect(subject.deliver!(from_mail)).to eq success
        end
      end

      context "invalid mail" do
        before do
          expect(subject.client).to receive(:post).never
        end

        it "should raise an error" do
          expect { subject.deliver!(Mail.new) }.to raise_error(ArgumentError)
        end
      end

      context "API error response" do
        let(:failure) { SendgridApi::Result.new({error: {message: "Something went wrong"}}) }

        before do
          expect(subject.client).to receive(:post).and_return(failure)
        end

        it "should raise an exception" do
          expect { subject.deliver!(mail) }.to raise_error(SendgridApi::Error::DeliveryError)
        end
      end
    end

    describe "#header_to_hash" do
      let(:mail)     {
        Mail.new(
          from:     Mail::Address.new('"Tester" <from@address.com>'),
          to:       "to@address.com",
          reply_to: Mail::Address.new('"Reply" <reply@address.com>'),
          subject:  "Rspec test"
        )
      }

      it "should remove values from the header" do
        hash_keys = subject.send(:header_to_hash, mail).keys
        expect(hash_keys).not_to include("To")
        expect(hash_keys).not_to include("From")
        expect(hash_keys).not_to include("Subject")
        expect(hash_keys).to     include("Reply-To")
      end
    end
  end
end
