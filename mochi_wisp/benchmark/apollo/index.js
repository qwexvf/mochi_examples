import { ApolloServer } from '@apollo/server'
import { startStandaloneServer } from '@apollo/server/standalone'

const typeDefs = `
  type Query {
    users: [User!]!
    user(id: ID!): User
  }
  type User {
    id: ID!
    name: String!
    email: String!
    posts: [Post!]!
  }
  type Post {
    id: ID!
    title: String!
    body: String!
  }
`

const users = Array.from({ length: 10 }, (_, i) => ({
  id: String(i + 1),
  name: `User ${i + 1}`,
  email: `user${i + 1}@example.com`,
}))

const postsFor = (userId) =>
  Array.from({ length: 5 }, (_, i) => ({
    id: `${userId}-${i + 1}`,
    title: `Post ${userId}-${i + 1}`,
    body: `Body of post ${userId}-${i + 1}`,
  }))

const resolvers = {
  Query: {
    users: () => users,
    user: (_, { id }) => users.find((u) => u.id === id) ?? null,
  },
  User: {
    posts: (user) => postsFor(user.id),
  },
}

const useCache = process.env.DOCUMENT_CACHE !== 'false'

const server = new ApolloServer({
  typeDefs,
  resolvers,
  ...(useCache ? {} : { documentStore: null }),
})
const { url } = await startStandaloneServer(server, {
  listen: { port: 4002, host: '0.0.0.0' },
})
console.log(`Apollo Server ready at ${url}`)
