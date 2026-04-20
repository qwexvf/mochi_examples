import { createServer } from 'node:http'
import { createYoga, createSchema } from 'graphql-yoga'

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

const useCache = process.env.DOCUMENT_CACHE !== 'false'

const yoga = createYoga({
  ...(useCache ? { documentStore: new Map() } : {}),
  schema: createSchema({
    typeDefs: `
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
    `,
    resolvers: {
      Query: {
        users: () => users,
        user: (_, { id }) => users.find((u) => u.id === id) ?? null,
      },
      User: {
        posts: (user) => postsFor(user.id),
      },
    },
  }),
  graphiql: false,
  logging: false,
})

const server = createServer(yoga)
server.listen(4003, '0.0.0.0', () => {
  console.log('GraphQL Yoga listening on port 4003')
})
