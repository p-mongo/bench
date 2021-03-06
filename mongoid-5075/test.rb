#!/usr/bin/env ruby



require 'bundler/inline'



gemfile do

  source 'https://rubygems.org'

  gem 'mongoid', '7.2.2'

end



require 'mongoid'



Mongoid.configure { |c| c.clients.default = { hosts: ['localhost:14920'], database: 'test' } }



puts Mongoid::VERSION

puts Mongo::VERSION



class Article

  include Mongoid::Document

  has_many :comments, autosave: true

end



class Comment

  include Mongoid::Document

  belongs_to :article, required: false

end

Article.delete_all
Comment.delete_all


comment = Comment.create!
p comment

test = 3


case test
when 1
  article = Article.create!(

    comment_ids: [comment.id],

    id: '1234',

  )
when 2
  article = Article.create!(

    comments: [comment],

    id: '1234',

  )
when 3
  article = Article.create!(

    comment_ids: [comment.id],

    id: '1234',

  )
  comment.save!
end

p article
p comment
p article.comments.first



pp article.comments.count #=> 1

pp article.comments.criteria.selector['article_id'] # => Gives a random id

pp article.comments.context.view.count # => 1



article.reload



pp article.comments.count # => 0

pp article.comments.criteria.selector['article_id'] #=> '123'

pp article.comments.context.view.count # => 0
