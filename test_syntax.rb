require 'async'

def test_method
  puts "Starting test"
  
  result = ::Async do |task|
    puts "In async block"
    42
  end
  
  puts "Result: #{result.wait}"
end

test_method