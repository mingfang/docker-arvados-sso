user = User.new(:email => "test@example.com")
user.password = "password"
user.save!
