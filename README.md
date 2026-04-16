# Large Project - COP4331C, Processes for Object-Oriented Software Development (POOSD)
In this project, we designed, developed, deployed, and present a Personal Calendar web application.
Each user on the app can create an account, log in, and manage their own tasks. This app is enhanced with AI suggestions for users.

## Features of the app
* User Authentication:
  - Registration (Sign up)
  - Login
  - Password Reset
  - Email Authentication
* Task Management (per user)
  - Add tasks
  - Edit tasks
  - Delete tasks
  - Search tasks
  - Receive AI suggestions
  - Share tasks with other users (stretch goal)

## Technologies Used
A MERN (MongoDB, Express.js, React.js, and Node.js) stack, provided through Digital Ocean, was used in a droplet. The domain
name was obtained through GoDaddy.

## How To Access Application (as of April 16, 2026)
**http://calendarplusplus.xyz/**

## Deployment Notes
* iOS universal links require the app entitlement `applinks:calendarplusplus.xyz` and the server endpoint `/.well-known/apple-app-site-association`.
* The checked-in nginx example is at `backend/deploy/nginx-calendarplusplus.conf`.
* nginx must keep `client_max_body_size 24m;` so larger base64 JSON image uploads from mobile are not rejected before Express handles them.

## AI Use
We acknowledge the use of AI to help set up, debug, and configure this application, helping us learn along the way.

## Meet the Dev team
* Ryan Murphy: Project Manager / Front-End
* Mohib Ahmed: Back-End / Mobile
* Jason Comras: Front-End
* Austin Robinson: Database
* Jonathan Slattery: API
* Tyler Wheelhouse: Mobile
* Anthony Mahon: Back-End / Front-End
* Adam Lugo: Back-End


University of Central Florida, Spring 2026.
