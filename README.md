# GenFact Demo backend

This is the code for the GenFact demo backend as part of CHI Expert. The frontend is currently kept in a [separate repo][frontend].

[frontend]: https://github.com/probcomp/genfact_demo

## GenFact Demo

In this demo, the user provides a sentence or tweet about a doctor. They then choose their preferred interpretation of the sentence from the interpretations GenFact/Genparse discovers (e.g. in "Dr. Ryan is a great doctor," is Ryan a first name or a last name?). Finally, the user can then check this interpretation against a database to learn about potential doctor, business, and doctor-business matches. Additionally, the user sees the match uncertainty, which describes both the relative likelihood of each match and the likelihood that there is no match in the database.

## Installing for development

1. Install Julia version 1.10.
2. Run `julia --project=$repo_root -e "using Pkg; Pkg.instantiate()"
2. Run `bash temp.sh`.
3. Run `bash pycall_setup.sh`.

## Usage

To start the backend:

```bash
bash serve.sh
```

## Routes

Documented on Linear [here][linear_spec]. For a simple listing/reminder of routes and their supported HTTP methods, run the server and navigate to the `/docs` endpoint.

[linear_spec]: https://linear.app/chi-fro/issue/FACT-28/genfact-frontend

## Developing

### Running tests

Currently test-running is broken. :( The branch `allow-running-tests` illustrates a possible way to fix this, however it's badly out of date and was not worth pushing on until after the demo, due to the risk of breaking the app and setting people back a few hours.

## Deploying, the hard way

The following sections describe how to deploy a new instance of the web app to a fresh Google Cloud VM (Compute Engine instance). We assume you already have an SSH session on the VM.

(Yes, this is ugly. unfortunately the demo crunch meant we didn't have time to learn a better way to deploy a Julia/Oxygen app.)

### Clone this repo
```bash
sudo mkdir -p /srv
sudo git clone genfact-demo /srv/genfact-demo
sudo chown -R "${USER:?}" /srv/genfact-demo
```

### Create admin group and set repo permissions
```bash
groupadd genfactdemo-admin
chgrp -R genfactdemo-admin /srv/genfact-demo
chmod -R g+rwxs /srv/genfact-demo
chmod -R o+r /srv/genfact-demo
# insecure hack :(
# but it worked.
chmod o+rw /srv/genfact-demo/Manifest.toml

# Add all necessary users to group
sudo usermod -a -G genfactdemo-admin "${USER:?}"
```

### Install Julia globally
```bash
julia_url=https://julialang-s3.julialang.org/bin/linux/x64/1.10/julia-1.10.4-linux-x86_64.tar.gz
julia_file="$HOME"/julia-1.10.tar.gz
julia_extracted="$HOME"/julia-1.10.4
julia_final=/opt/julia/"$(basename "${julia_extracted:?}")"
curl "${julia_url:?}" -o "${julia_file:?}"
tar -C "${HOME:?}" -xaf "${julia_file:?}"  # creates $julia_extracted

sudo mkdir -p /opt/julia
cp -r "${julia_extracted:?}" /opt/julia  #
ln -s "${julia_final:?}"/bin/julia /usr/local/bin/julia
```

### Create GenFact Demo user
```bash
useradd --system genfact-demo
```

### Setup Julia environment for GenFact-Demo user
```bash
sudo mkdir -p /srv/julia/.julia
sudo chown -R genfact-demo /srv/julia
sudo chgrp -R genfact-demo /srv/julia
# insecure hack :(
# but it worked.
sudo chmod -R o+rws /srv/julia/.julia

> /etc/profile.d/julia.sh sudo cat <<<EOF
export JULIA_DEPOT_PATH="/srv/julia/.julia"
EOF
```

### Create log file
```bash
# it's not used, but technically serve.sh requires it to exist
# and be writeable by genfact-demo, otherwise it won't run.
# we could fix this, but it's not obviously worth it until after
# the demo.
touch /srv/genfact-demo/output.log
chgrp genfactdemo-admin /srv/genfact-demo/output.log
chmod g+rw /srv/genfact-demo/output.log
chmod o+rw /srv/genfact-demo/output.log
```

### Set up systemd service
```bash
sudo ln -s /srv/genfact-demo/genfact-demo.service /etc/systemd/system/genfact-demo.service
sudo systemctl enable genfact-demo.service
sudo systemctl start genfact-demo.service
# Optional: check status
sudo systemctl status genfact-demo.service
```
