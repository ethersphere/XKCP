module example

go 1.24.0

replace github.com/example/keccak => ../go_keccak

require (
	github.com/example/keccak v0.0.0
	golang.org/x/crypto v0.43.0
)

require golang.org/x/sys v0.41.0
