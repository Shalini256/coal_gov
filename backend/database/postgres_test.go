package database

import "testing"

func TestRebind(t *testing.T) {
	input := "SELECT * FROM records WHERE id = ? AND note = '?' -- ?\nAND owner_id = ? /* ? */"
	want := "SELECT * FROM records WHERE id = $1 AND note = '?' -- ?\nAND owner_id = $2 /* ? */"
	if got := rebind(input); got != want {
		t.Fatalf("rebind() = %q, want %q", got, want)
	}
}

func TestShouldReturnID(t *testing.T) {
	tests := []struct {
		query string
		want  bool
	}{
		{"INSERT INTO workers (full_name) VALUES (?)", true},
		{"INSERT INTO workers (full_name) VALUES (?), (?)", false},
		{"INSERT INTO workers (full_name) VALUES (?) ON CONFLICT DO NOTHING", false},
		{"UPDATE workers SET full_name = ? WHERE id = ?", false},
	}

	for _, test := range tests {
		if got := shouldReturnID(test.query); got != test.want {
			t.Errorf("shouldReturnID(%q) = %t, want %t", test.query, got, test.want)
		}
	}
}
