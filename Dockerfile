FROM julia:1.10.4

WORKDIR /usr/local/app

COPY . .

# Set up a virtual environment
RUN ["bash", "temp.sh"]
RUN ["bash", "pycall_setup.sh"]
RUN ["julia", "--project=.", "-e", "using Pkg; Pkg.activate(\".\"); Pkg.instantiate()"]

# run the app
# jac: entrypoint might be more appropriate but means we can't e.g. start a
# shell in the container in order to inspect the container.
EXPOSE 8888/tcp
CMD ["julia", "--project=.", "-e", "include(\"app.jl\")"]
