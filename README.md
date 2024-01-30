# Laravel Docker-Compose Setup

This repository provides a Docker Compose configuration to set up a Laravel development environment quickly.

## Table of Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Usage](#usage)
- [Contributing](#contributing)
- [License](#license)

## Introduction

This project aims to simplify the setup of a Laravel development environment using Docker Compose. It includes configurations for a web server using NGINX, PHP, and a database, making it easy to start developing Laravel applications in a containerized environment.

## Prerequisites

Before you begin, ensure you have the following prerequisites installed on your system:

- [Docker](https://www.docker.com/get-started)
- [Docker Compose](https://docs.docker.com/compose/install/)
- [Git](https://git-scm.com/downloads) (if you want to clone this repository)

## Getting Started

1. **Clone this repository** to your local machine (or download and extract it):
   ```bash
   git clone https://github.com/adiyudhanegara/docker-laravel.git

2. **Change the text below** with your project configuration (*.env*)
    ```bash
    PROJECT_NAME=laravel #change your project name
    PROJECT_IP= 172.22.0 #make sure this IP address is unique on your network to avoid conflicts

3. **Run this command** to build your docker
    ```bash
    docker-compose build

4. **Start your docker** by this command
    ```bash
    docker-compose up

3. **Clone your project inside** *./webroot/* **OR** You can initiate a new project using by using *composer*
    ```bash
    docker-compose exec app zsh
    composer create-project laravel/laravel project_name
    composer install
    ```
After that you can use zsh to run your command such as
    ```
    php artisan migrate
    ```