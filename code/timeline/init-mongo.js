// MongoDB initialization script for timeline service
// This script sets up the timeline database and collection with sample mission events

// Create admin user for timeline database
db = db.getSiblingDB('admin');
db.createUser({
  user: 'admin',
  pwd: 'password',
  roles: [
    { role: 'readWrite', db: 'timeline' },
    { role: 'dbAdmin', db: 'timeline' }
  ]
});

// Switch to timeline database
db = db.getSiblingDB('timeline');

// Create events collection
db.createCollection('events');

// Insert sample mission timeline events
db.events.insertMany([
  {
    name: "Mission Start",
    time: new Date("1969-07-16T13:32:00Z"),
    description: "Apollo 11 mission begins with launch from Kennedy Space Center"
  },
  {
    name: "Earth Orbit Achieved",
    time: new Date("1969-07-16T13:44:00Z"),
    description: "Spacecraft successfully enters Earth orbit"
  },
  {
    name: "Trans-Lunar Injection",
    time: new Date("1969-07-16T16:22:00Z"),
    description: "S-IVB stage fires to send spacecraft toward the Moon"
  },
  {
    name: "Lunar Orbit Insertion",
    time: new Date("1969-07-19T17:21:00Z"),
    description: "Spacecraft enters lunar orbit"
  },
  {
    name: "Lunar Module Descent",
    time: new Date("1969-07-20T20:17:00Z"),
    description: "Eagle lunar module begins descent to lunar surface"
  },
  {
    name: "The Eagle Has Landed",
    time: new Date("1969-07-20T20:17:40Z"),
    description: "Lunar module successfully lands on the Moon"
  },
  {
    name: "First Step on Moon",
    time: new Date("1969-07-21T02:56:00Z"),
    description: "Neil Armstrong becomes the first human to walk on the Moon"
  },
  {
    name: "Lunar Module Ascent",
    time: new Date("1969-07-21T17:54:00Z"),
    description: "Eagle begins ascent from lunar surface"
  },
  {
    name: "Lunar Orbit Rendezvous",
    time: new Date("1969-07-21T21:35:00Z"),
    description: "Eagle docks with Columbia command module"
  },
  {
    name: "Trans-Earth Injection",
    time: new Date("1969-07-22T04:55:00Z"),
    description: "Spacecraft begins journey back to Earth"
  },
  {
    name: "Splashdown",
    time: new Date("1969-07-24T16:50:00Z"),
    description: "Apollo 11 safely returns to Earth"
  }
]);

// Create index on time field for efficient queries
db.events.createIndex({ "time": 1 });

print("Timeline database initialized with sample mission events");
print("Total events inserted: " + db.events.countDocuments()); 