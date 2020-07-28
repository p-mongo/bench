require 'mongo'
require 'ruby-progressbar'
require 'base64'

Mongo::Logger.logger.level = Logger::INFO
client = Mongo::Client.new(['localhost:27300'], database: 'test')

collection = client['data']
collection.drop

client.use('admin').database.command(enableSharding: 'test')
client.use('admin').database.command(shardCollection: 'test.data',
  key: {_id: 'hashed'},
)

# 10k total documents with:
# - an indexed counter
# - a non-indexed counter
# - an indexed text field
# - a non-indexed text field

ROUNDS = 1000
BATCH_SIZE = 1000

bar = ProgressBar.create(total: ROUNDS, format: '%c / %C |%B| %p%% %e')

i = 0
ROUNDS.times do
  docs = 1.upto(BATCH_SIZE).map do
    i += 1
    text_length = 10 + (rand * 90).to_i
    {
      counter: i,
      slow_counter: i,
      text: Base64.encode64(SecureRandom.random_bytes(100))[0...text_length],
      slow_text: Base64.encode64(SecureRandom.random_bytes(100))[0...text_length] + 'x'*10000,
    }
  end

  collection.insert_many(docs)
  bar.increment
end

collection.indexes.create_one(counter: 1)
collection.indexes.create_one(text: 1)
