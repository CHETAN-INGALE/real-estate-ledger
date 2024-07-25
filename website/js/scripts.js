document.addEventListener('DOMContentLoaded', () => {
    const nav = document.getElementById('nav');
    const navLinks = document.querySelectorAll('nav ul li a');
    const sections = document.querySelectorAll('main section');
    const loginForm = document.getElementById('login-form');
    const homeSection = document.getElementById('home');
    const homeLogin = document.querySelector('.home-login');
    const homeImage = document.querySelector('.home-image');
    const propertyList = document.getElementById('property-list');

    // Mock data for registered properties
    const registeredProperties = [
        {
            id: 'P001',
            owner: 'John Doe',
            type: 'Apartment',
            address: '123 Main St, City',
            aadhaar: '1234-5678-9101',
            purchaseDate: '2023-01-15'
        },
        {
            id: 'P002',
            owner: 'Jane Smith',
            type: 'House',
            address: '456 Elm St, City',
            aadhaar: '2345-6789-1011',
            purchaseDate: '2022-07-30'
        }
    ];

    // Handle navigation link clicks
    navLinks.forEach(link => {
        link.addEventListener('click', (e) => {
            e.preventDefault();

            // Remove active class from all links
            navLinks.forEach(link => link.classList.remove('active'));

            // Add active class to the clicked link
            e.target.classList.add('active');

            // Hide all sections
            sections.forEach(section => section.classList.remove('active'));

            // Show the corresponding section
            const sectionId = e.target.getAttribute('data-section');
            document.getElementById(sectionId).classList.add('active');
            
            // Populate the view section with property data
            if (sectionId === 'view') {
                propertyList.innerHTML = '';
                registeredProperties.forEach(property => {
                    const propertyDiv = document.createElement('div');
                    propertyDiv.classList.add('property-item');
                    propertyDiv.innerHTML = `
                        <p><strong>Property ID:</strong> ${property.id}</p>
                        <p><strong>Owner:</strong> ${property.owner}</p>
                        <p><strong>Type:</strong> ${property.type}</p>
                        <p><strong>Address:</strong> ${property.address}</p>
                        <p><strong>Aadhaar Number:</strong> ${property.aadhaar.replace(/\d{4}(?=\d)/g, 'XXXX-')}</p>
                        <p><strong>Date of Purchase:</strong> ${property.purchaseDate}</p>
                    `;
                    propertyList.appendChild(propertyDiv);
                });
            }
        });
    });

    // Show the home section by default
    sections[0].classList.add('active');

    // Handle login form submission
    loginForm.addEventListener('submit', (e) => {
        e.preventDefault();
        const username = document.getElementById('username').value;
        const password = document.getElementById('password').value;

        // Simulate login success for demonstration purposes
        if (username === "admin" && password === "password") { // Replace with actual authentication logic
            alert('Login successful!');
            
            // Hide login section and show homepage content
            homeLogin.style.display = 'none';
            homeImage.style.flex = '1';
            nav.classList.remove('hidden');
            sections.forEach(section => section.classList.remove('active'));
            homeSection.classList.add('active');
        } else {
            alert('Invalid username or password');
        }
    });
});
