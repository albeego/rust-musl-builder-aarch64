build:
	docker build . -t albeego/rust-musl-builder-aarch64:0.0.1
push:
	docker push albeego/rust-musl-builder-aarch64:0.0.1